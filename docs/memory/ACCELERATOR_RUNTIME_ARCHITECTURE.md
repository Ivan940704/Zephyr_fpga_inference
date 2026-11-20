# Production accelerator runtime architecture

Date: 2026-09-06 (Asia/Taipei)

Status: RTL datapath through DeepFilter is implemented and unit-tested.  PS7,
DMA, AXI-Lite control, reset/CDC block-design wiring, and bitstream are pending.

## System blocks and links

```mermaid
flowchart TB
  subgraph PS[PS]
    CPU[CPU / PYNQ software]
    DDRC[DDR controller]
    DRAM[(DRAM)]
    DMA[AXI DMA set\nnot yet integrated]
    CTRL[AXI-Lite control regs\nnot yet integrated]
  end

  subgraph PL[PL]
    MB[LayerNorm mailbox\n64 B PL to PS / 782 B PS to PL]
    FD[Feature dispatcher\n64 B FB + mapped SB features]
    FSM[Global FSM]
    SUB[Sequential-v4 PE/memory subsystem\nmemory service + context store + job controller + frozen PE array]
    CS[DF coefficient store\n1,152 B / 9 contexts]
    DF[Sequential DeepFilter\n5-frame spectrum + 5/3/1 MAC]
  end

  DRAM <--> DDRC
  CPU <--> CTRL
  CPU <--> MB
  DDRC -->|static v4 parameter image| SUB
  DDRC <--> DMA
  DMA -->|64 B fullband INT8| FD
  DMA -->|512 B noisy complex INT8| DF
  FD -->|stage/context/source feature| SUB
  SUB -->|64 B FB projection| MB
  MB -->|782 B normalized SB payload| FD
  SUB -->|DF projection bytes| CS
  CS -->|signed INT8 coefficients| DF
  DF -->|256 x 64-bit INT32 complex| DMA
  FSM -->|stage load and job lifecycle| SUB
  FSM -->|publish / PS-return barriers| MB
  FSM -->|frame and consume barriers| CS
  FSM -->|DF start / done / output drain| DF

  classDef control fill:#eaf5df,stroke:#6aa342,color:#111
  classDef payload fill:#fff0df,stroke:#ef842d,color:#111
  classDef mailbox fill:#fdeaea,stroke:#b90000,color:#111
  classDef pending fill:#f2f2f2,stroke:#777,color:#111,stroke-dasharray:5 5
  class FSM control
  class SUB,CS,DF,FD payload
  class MB mailbox
  class DMA,CTRL pending
```

Orange paths carry model operands/results, red is the PS LayerNorm round trip,
and green is lifecycle/control.  The FSM never carries payload bytes.

## Differences from the supplied conceptual diagram

| Conceptual diagram | Current production RTL |
|---|---|
| PE array and sequential-v4 memory are independent peers | They are frozen inside one `sequential_v4_pe_memory_subsystem`, together with the job controller and recurrent-context store. |
| DDR connects generically to model input/output/weight | Static v4 parameters use the custom read-only AXI master; fullband input, noisy spectrum, and final results require separate AXI DMA paths. |
| PS mailbox connects broadly to the PE array | The mailbox is restricted to the LayerNorm ABI: 64-byte fullband projection to PS and 782-byte normalized subband payload back to PL. |
| FSM connects directly to memory and PE | It commands the subsystem at stage/job barriers; feature and coefficient bytes pass through dedicated dispatcher/store blocks. |
| DeepFilter is not shown | A 1,152-byte coefficient store and a five-frame sequential DeepFilter engine now sit after subband projection. |

## Global FSM states

```mermaid
stateDiagram-v2
  [*] --> IDLE
  IDLE --> FB_LOAD_REQ: start and both ingress packets ready
  FB_LOAD_REQ --> FB_LOAD_WAIT: memory accepts stage request
  FB_LOAD_WAIT --> FB_RUN: requested FB stage loaded
  FB_RUN --> FB_LOAD_REQ: next FB stage (0,1,2)
  FB_RUN --> FB_SEND: stage 2 projection complete
  FB_SEND --> WAIT_PS: 64-byte mailbox publish complete
  WAIT_PS --> SB_LOAD_REQ: matching 782-byte PS return committed
  SB_LOAD_REQ --> SB_LOAD_WAIT: memory accepts SB stage request
  SB_LOAD_WAIT --> SB_RUN: requested branch stage loaded
  SB_RUN --> SB_LOAD_REQ: next context / branch / stage
  SB_RUN --> DF_RUN: stages 3..11 complete and 9 coefficient contexts valid
  DF_RUN --> OUTPUT: 256-bin DeepFilter result ready
  OUTPUT --> DONE: final AXIS beat accepted
  DONE --> IDLE
  IDLE --> ERROR: pre-existing interface fault
  FB_LOAD_REQ --> ERROR: abort / timeout / memory / PE fault
  FB_LOAD_WAIT --> ERROR: abort / timeout / memory / PE fault
  FB_RUN --> ERROR: abort / timeout / PE fault
  FB_SEND --> ERROR: abort / timeout / mailbox fault
  WAIT_PS --> ERROR: abort / timeout / mailbox fault
  SB_LOAD_REQ --> ERROR: abort / timeout / memory / PE fault
  SB_LOAD_WAIT --> ERROR: abort / timeout / memory / PE fault
  SB_RUN --> ERROR: abort / timeout / PE fault
  DF_RUN --> ERROR: abort / timeout / DF fault
  OUTPUT --> ERROR: abort / timeout / output fault
  ERROR --> IDLE: coordinated rst_n only
```

The physical stage order in shared-engine production mode is
`0,1,2,3,6,9,4,7,10,5,8,11`.  States are barriers, not one-cycle pulses:
valid/start signals remain asserted until the corresponding ready handshake,
and completion is not retired until the PE boundary is idle.

## Pre-programming gate

The full RTL top routes with zero routing errors and zero unconstrained
internal endpoints, but 100 MHz routed-OOC WNS is `-0.467 ns`.  The worst path
is inside the frozen recurrent-context store.  Before PS7/DMA block-design
implementation, the team must choose one of two production directions:

1. keep 100 MHz and explicitly unfreeze/pipeline the recurrent-context error
   path; or
2. keep all frozen bytes and select a lower FCLK with new timing/throughput
   acceptance criteria.

No bitstream should be generated or programmed until that decision and the
subsequent full block-design timing/CDC/DRC gate pass.
