#define _POSIX_C_SOURCE 200809L

/* Portable native LayerNorm kernels for the PYNQ inference hot path.
 *
 * Build on the target (or a host for contract tests) with:
 *   cc -O3 -std=c11 -fPIC -shared -o libzephyr_native_layernorm.so \
 *      native_layernorm.c -lm
 *
 * Inputs are float32 because that is the frozen parameter/runtime storage
 * format. Accumulation and affine arithmetic use double to match the existing
 * NumPy float64 reference before round-to-nearest, ties-to-even quantization.
 */
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <time.h>

#define REG_COMMAND_WORD (0x000u / 4u)
#define REG_IMAGE_VERSION_WORD (0x0A4u / 4u)
#define REG_INPUT_BUFFER_STATUS_WORD (0x070u / 4u)
#define DMA_MM2S_ADDRESS_WORD (0x18u / 4u)
#define DMA_MM2S_LENGTH_WORD (0x28u / 4u)
#define DMA_S2MM_STATUS_WORD (0x34u / 4u)
#define DMA_S2MM_ADDRESS_WORD (0x48u / 4u)
#define DMA_S2MM_LENGTH_WORD (0x58u / 4u)
#define DMA_IOC_IRQ (1u << 12)
#define DMA_ERROR_MASK 0x00000770u

static uint64_t monotonic_ns(void)
{
    struct timespec now;

    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        return 0;
    }
    return (uint64_t)now.tv_sec * 1000000000ull + (uint64_t)now.tv_nsec;
}

static int quantize_one(double value, double scale, int8_t *output)
{
    double rounded;

    if (!isfinite(value)) {
        return 2;
    }
    rounded = nearbyint(value / scale);
    if (rounded > 127.0) {
        rounded = 127.0;
    } else if (rounded < -127.0) {
        rounded = -127.0;
    }
    *output = (int8_t)rounded;
    return 0;
}

int zephyr_layer_norm_quantize_f32(
    const float *values,
    const float *weight,
    const float *bias,
    uint32_t length,
    double scale,
    double epsilon,
    int8_t *output)
{
    double sum = 0.0;
    double square_sum = 0.0;
    double mean;
    double inverse_std;
    uint32_t index;

    if (values == NULL || weight == NULL || bias == NULL || output == NULL ||
        length == 0 || !isfinite(scale) || scale <= 0.0 ||
        !isfinite(epsilon) || epsilon < 0.0) {
        return 1;
    }
    for (index = 0; index < length; ++index) {
        if (!isfinite(values[index]) || !isfinite(weight[index]) ||
            !isfinite(bias[index])) {
            return 2;
        }
        sum += (double)values[index];
    }
    mean = sum / (double)length;
    for (index = 0; index < length; ++index) {
        const double centered = (double)values[index] - mean;
        square_sum += centered * centered;
    }
    inverse_std = 1.0 / sqrt(square_sum / (double)length + epsilon);
    for (index = 0; index < length; ++index) {
        const double normalized = ((double)values[index] - mean) * inverse_std;
        const double affine = normalized * (double)weight[index] + (double)bias[index];
        const int status = quantize_one(affine, scale, &output[index]);
        if (status != 0) {
            return status;
        }
    }
    return 0;
}

int zephyr_build_subband_payload_f32(
    const float *magnitude,
    const int8_t *fullband_projection,
    const uint16_t *source_indices,
    const uint16_t *vector_offsets,
    const float *weight,
    const float *bias,
    const double *scales,
    double fullband_projection_scale,
    double epsilon,
    int8_t *output)
{
    uint32_t vector;

    if (magnitude == NULL || fullband_projection == NULL ||
        source_indices == NULL || vector_offsets == NULL || weight == NULL ||
        bias == NULL || scales == NULL || output == NULL ||
        !isfinite(fullband_projection_scale) ||
        fullband_projection_scale <= 0.0 || !isfinite(epsilon) || epsilon < 0.0) {
        return 1;
    }
    for (vector = 0; vector < 9; ++vector) {
        const uint32_t start = vector_offsets[vector];
        const uint32_t end = vector_offsets[vector + 1];
        const uint32_t length = end - start;
        double sum = 0.0;
        double square_sum = 0.0;
        double mean;
        double inverse_std;
        uint32_t position;

        if (length == 0 || !isfinite(scales[vector]) || scales[vector] <= 0.0) {
            return 1;
        }
        for (position = start; position < end; ++position) {
            const uint16_t source = source_indices[position];
            const double value = source < 256
                ? (double)magnitude[source]
                : (double)fullband_projection[source - 256] * fullband_projection_scale;
            if (!isfinite(value) || !isfinite(weight[position]) ||
                !isfinite(bias[position])) {
                return 2;
            }
            sum += value;
        }
        mean = sum / (double)length;
        for (position = start; position < end; ++position) {
            const uint16_t source = source_indices[position];
            const double value = source < 256
                ? (double)magnitude[source]
                : (double)fullband_projection[source - 256] * fullband_projection_scale;
            const double centered = value - mean;
            square_sum += centered * centered;
        }
        inverse_std = 1.0 / sqrt(square_sum / (double)length + epsilon);
        for (position = start; position < end; ++position) {
            const uint16_t source = source_indices[position];
            const double value = source < 256
                ? (double)magnitude[source]
                : (double)fullband_projection[source - 256] * fullband_projection_scale;
            const double normalized = (value - mean) * inverse_std;
            const double affine = normalized * (double)weight[position] +
                (double)bias[position];
            const int status = quantize_one(affine, scales[vector], &output[position]);
            if (status != 0) {
                return status;
            }
        }
    }
    return 0;
}

static int dequantize_output_batch_i32(
    const int32_t *accumulators,
    uint32_t frame_count,
    const float *band_scales,
    float *complex_output)
{
    uint64_t element;
    const uint64_t bin_count = (uint64_t)frame_count * 256u;

    if (accumulators == NULL || band_scales == NULL || complex_output == NULL ||
        frame_count == 0) {
        return 1;
    }
    for (element = 0; element < bin_count; ++element) {
        const uint32_t bin = (uint32_t)(element & 255u);
        const uint32_t band = bin < 32 ? 0 : (bin < 128 ? 1 : 2);
        const float scale = band_scales[band];
        if (!isfinite(scale) || scale <= 0.0f) {
            return 2;
        }
        complex_output[2 * element] = (float)accumulators[2 * element] * scale;
        complex_output[2 * element + 1] =
            (float)accumulators[2 * element + 1] * scale;
    }
    return 0;
}

int zephyr_dequantize_output_i32(
    const int32_t *accumulators,
    const float *band_scales,
    float *complex_output)
{
    return dequantize_output_batch_i32(
        accumulators, 1u, band_scales, complex_output);
}

int zephyr_dequantize_output_batch_i32(
    const int32_t *accumulators,
    uint32_t frame_count,
    const float *band_scales,
    float *complex_output)
{
    return dequantize_output_batch_i32(
        accumulators, frame_count, band_scales, complex_output);
}

int zephyr_dma_submit_and_start(
    volatile uint32_t *control,
    volatile uint32_t *io_dma,
    volatile uint32_t *spectrum_dma,
    uint32_t output_address,
    uint32_t fullband_address,
    uint32_t fullband_bytes,
    uint32_t spectrum_address,
    uint64_t timeout_ns,
    uint64_t *start_ns,
    uint32_t *last_status)
{
    const uint64_t deadline = monotonic_ns() + timeout_ns;
    uint32_t status;

    if (control == NULL || io_dma == NULL || spectrum_dma == NULL ||
        start_ns == NULL || last_status == NULL || fullband_bytes == 0) {
        return 1;
    }
    io_dma[DMA_S2MM_ADDRESS_WORD] = output_address;
    io_dma[DMA_S2MM_LENGTH_WORD] = 2048u;
    io_dma[DMA_MM2S_ADDRESS_WORD] = fullband_address;
    io_dma[DMA_MM2S_LENGTH_WORD] = fullband_bytes;
    spectrum_dma[DMA_MM2S_ADDRESS_WORD] = spectrum_address;
    spectrum_dma[DMA_MM2S_LENGTH_WORD] = 512u;
    __sync_synchronize();
    for (;;) {
        status = control[REG_INPUT_BUFFER_STATUS_WORD];
        if ((status & 3u) == 3u) {
            break;
        }
        if (monotonic_ns() >= deadline) {
            *last_status = status;
            return 2;
        }
    }
    *start_ns = monotonic_ns();
    control[REG_COMMAND_WORD] = 1u;
    __sync_synchronize();
    (void)control[REG_IMAGE_VERSION_WORD];
    *last_status = status;
    return 0;
}

int zephyr_dma_wait_output(
    volatile uint32_t *io_dma,
    uint64_t timeout_ns,
    uint32_t *last_status)
{
    const uint64_t deadline = monotonic_ns() + timeout_ns;
    uint32_t status;

    if (io_dma == NULL || last_status == NULL) {
        return 1;
    }
    for (;;) {
        status = io_dma[DMA_S2MM_STATUS_WORD];
        if (status & DMA_ERROR_MASK) {
            *last_status = status;
            return 3;
        }
        if (status & DMA_IOC_IRQ) {
            io_dma[DMA_S2MM_STATUS_WORD] = DMA_IOC_IRQ;
            __sync_synchronize();
            *last_status = status;
            return 0;
        }
        if (monotonic_ns() >= deadline) {
            *last_status = status;
            return 2;
        }
    }
}
