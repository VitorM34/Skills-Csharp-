---
name: dotnet-production-diagnostics
description: Diagnosticar problemas de apps .NET em produção com as ferramentas oficiais - memory leak, CPU alta, app travada/deadlock, ThreadPool starvation (respostas lentas sob carga), crash e StackOverflow. Cobre dotnet-counters, dotnet-dump (SOS), dotnet-gcdump, dotnet-trace, dotnet-stack, dotnet-monitor, coleta de dump em crash (DOTNET_DbgEnableMiniDump), métricas de runtime, diagnóstico dentro de containers (sidecar, ptrace/seccomp) e cuidados de segurança. Use quando o usuário relatar lentidão, memória crescendo, travamento, crash sem causa ou pedir "como investigo isso em produção". Based on official Microsoft Learn docs (.NET diagnostics, .NET 10).
---

# Diagnóstico de problemas em produção (.NET)

Só afirmar o que a doc oficial diz (fontes no fim). **Não adivinhe a causa:** primeiro confirme o sintoma com métricas, depois colete o artefato certo e só então conclua. Prevenção/instrumentação contínua: `dotnet-observability`, `aspnet-logging`, `aspnet-health-checks`. Causas de código mais comuns: `csharp-async-await` (sync-over-async), `dotnet-concurrency-threading`, `dotnet-memory-disposable`, `aspnet-caching`, `efcore-sql-performance`.

> ⚠ **Apps publicados com Native AOT** (`dotnet-native-aot-trimming`): o debugger gerenciado não funciona, **análise de heap gerenciado (`dotnet-gcdump`, `dumpheap`) não é suportada** e dumps exigem passos manuais; EventPipe/`dotnet-trace`/`dotnet-counters` funcionam parcialmente (exigem `EventSourceSupport=true`). Reproduza o problema no CoreCLR sempre que possível.

## Princípios (oficiais)
- Diagnóstico não substitui observabilidade: métricas/logs/traces são a primeira linha (`dotnet-observability`); **dumps, traces e GC dumps** entram quando isso não basta.
- **Confirme o efeito antes de coletar:** "identificar os efeitos do problema é a chave para achar a causa". Exemplo da doc: confirmar o vazamento vendo a memória crescer com `dotnet-counters` antes de gerar dump.
- **Dumps podem conter dados sensíveis** (memória inteira do processo): trate com as mesmas restrições de segurança. O tipo `Triage` remove informações pessoais (caminhos, senhas).
- Após coletar o dump de um processo com problema em produção, **reiniciar o processo é a remediação de curto prazo** (a doc diz que esse é o momento ideal).
- Para comparar ao longo do tempo (vazamento), colete **dois dumps** com o processo ainda rodando entre eles.
- **Instalação:** `dotnet tool install --global dotnet-counters` (idem `dotnet-dump`, `dotnet-gcdump`, `dotnet-trace`, `dotnet-stack`, `dotnet-monitor`). A doc também lista execução pontual com `dnx dotnet-counters ...` como opção recomendada, e downloads diretos.

## Pré-requisitos comuns das ferramentas (todas)
- Rodar **como o mesmo usuário do processo alvo ou como root**; senão a conexão falha.
- **Linux/macOS:** alvo e ferramenta precisam compartilhar a mesma variável **`TMPDIR`**, senão o comando dá *timeout*.
- Alvo escolhido por `-p|--process-id` ou `-n|--name`; liste processos com `dotnet-counters ps` / `dotnet-trace ps` / `dotnet-dump ps`.
- `DOTNET_ROOT` apontando para outra versão do .NET faz o `dotnet-dump` falhar com "não foi possível encontrar versão compatível do framework" (FAQ de dumps).

## Escolha por sintoma (fluxo da doc)
| Sintoma | 1º passo (confirmar) | Coleta | Análise |
|---|---|---|---|
| **Memória crescendo / OOM** | `dotnet-counters monitor` (heap/working set) | `dotnet-dump collect` (2 dumps no tempo) ou `dotnet-gcdump collect` | SOS `dumpheap -stat`, `dumpheap -mt`, `gcroot` |
| **CPU alta** | `dotnet-counters monitor --showDeltas` (`dotnet.process.cpu.time`) | `dotnet-trace collect` (Windows/qualquer SO), **`dotnet-trace collect-linux` (.NET 10+, Linux, root)** ou `perf` | PerfView (CPU Stacks / CallTree) ou Visual Studio (`.nettrace`) |
| **Travada / sem resposta (deadlock)** | threads acumulando; requisição que não retorna | `dotnet-dump collect` com o app travado | SOS `threads`, `clrstack -all`, `syncblk`, `setthread` |
| **Lenta sob carga (ThreadPool starvation)** | `dotnet-counters`: `dotnet.thread_pool.thread.count` subindo, fila crescendo | `dotnet-stack report` (contínuo) ou `dotnet-trace collect --clrevents waithandle` (intermitente, .NET 9+) | stacks bloqueados em `GetResultCore`/`Wait`; PerfView |
| **Crash / StackOverflow** | log "Stack overflow." com frames repetidos | dump em crash (`DOTNET_DbgEnableMiniDump=1`) | SOS (`ip2md`) / lldb / WinDbg / Visual Studio |

## 1) Memory leak (oficial: *Debug a memory leak*)
1. Confirme: `dotnet-counters monitor --refresh-interval 1 -p <PID>`; olhe `dotnet.gc.last_collection.memory.committed_size`, `dotnet.gc.last_collection.heap.size` (por geração: gen0/1/2, **loh**, **poh**), `dotnet.process.memory.working_set`. Crescimento contínuo da memória gerenciada confirma o vazamento (no exemplo oficial, de ~4 MB para mais de 20 MB após exercitar o endpoint).
2. Dump: `dotnet-dump collect -p <PID>` (Linux gera `core_YYYYMMDD_HHMMSS`).
3. Análise: `dotnet-dump analyze <dump>` → `dumpheap -stat` (tipos que mais ocupam: contagem e tamanho) → `dumpheap -mt <MT>` (instâncias do tipo) → **`gcroot <endereço>`** (quem mantém o objeto vivo). No exemplo oficial, a raiz era um `CustomerCache` com `List<Customer>` que mantinha os objetos vivos.
- **`dotnet-gcdump`** é a alternativa leve: coleta um GC dump de processo vivo via EventPipe (dispara um GC e reconstrói o grafo de raízes); serve para **comparar contagem de objetos em vários momentos**, analisar raízes e estatísticas por tipo. Opções: `-p/-n`, `-o`, `-t` (timeout, padrão 30 s), `-v`. **Só abre no PerfView/Visual Studio (Windows)**; não há como abrir `.gcdump` em outras plataformas.
- Em containers com limite de memória, ver "Containers" (dump grande pode estourar o limite).
- Teoria de GC/LOH/Dispose: `dotnet-memory-disposable`.

## 2) CPU alta (oficial: *Debug high CPU*)
- Confirme com `dotnet-counters monitor -n <app> --showDeltas`: `Last Delta` de `dotnet.process.cpu.time` (user/system) = segundos de CPU no período.
- **Use um profiler** para ver o que o código faz. `dotnet-trace collect` funciona em qualquer SO, mas **limitado por viés de safe-point e stacks só gerenciados**; um profiler ciente do kernel (ETW no Windows, `perf` no Linux) dá mais detalhe.
- **Linux, .NET 10+:** `sudo dotnet-trace collect-linux` (recomendado pela doc): une EventPipe + `perf_events`, stacks gerenciados **e nativos**, sem reiniciar o processo; exige **root, kernel ≥ 6.4 com `CONFIG_USER_EVENTS=y`**, tracefs montado, glibc ≥ 2.27 (Alpine 3.22 não atende). Deixe rodar ~20–30 s e pare (Ctrl+C/Enter). Abra o `.nettrace` no PerfView (**CPU Stacks**).
- **Linux com `perf`:** `export DOTNET_PerfMapEnabled=1` antes de iniciar o app; `sudo perf record -p <PID> -g`; `perf report`; flame graph opcional.
- **Windows:** `dotnet-trace collect -p <PID> --providers Microsoft-DotNETCore-SampleProfiler`, abrir no PerfView ("Thread Time (with StartStop Activities) Stacks" → CallTree) ou Visual Studio.
- Perfis do `dotnet-trace` (padrão se nenhum for informado: `dotnet-common` + `dotnet-sampled-thread-time`): `dotnet-common` (GC, loader, JIT, exceptions, threading…, baixo overhead), `dotnet-sampled-thread-time` (amostra stacks ~1 kHz), `gc-verbose`, `gc-collect`. O antigo `cpu-sampling` foi removido (não mede CPU de fato). Formatos de saída (`--format`): `NetTrace` (padrão), `Speedscope`, `Chromium`. `--duration hh:mm:ss`, `--clrevents`, `--providers`. Parar o trace pode levar **minutos** em apps grandes. Exceção não tratada durante o trace deixa o arquivo incompleto ⇒ para investigar crash use dump em crash.
- Existe a métrica `dotnet.exceptions` (contador de exceções lançadas, por `error.type`) para acompanhar a taxa de exceções.

## 3) App travada / deadlock (oficial: *Debug a deadlock*)
1. Com o app travado (10–15 s), `dotnet-dump collect -p <PID>` (Linux pode exigir `sudo`).
2. `dotnet-dump analyze <dump>`: `threads` (visão geral) → `clrstack -all` (stacks gerenciados de todas as threads; muitas esperando em `Monitor.ReliableEnter`) → **`syncblk`** (colunas **MonitorHeld** e **Owning Thread Info**: quem segura cada lock) → `setthread <índice>` + `clrstack` para ver o que as donas dos locks fazem. No exemplo, cada thread dona tentava readquirir lock que já mantinha; as 300+ restantes esperavam nesses locks.
- Outros comandos SOS úteis da lista oficial: `parallelstacks` (stacks agrupados, como o Parallel Stacks do VS), `dumpasync` (state machines async no heap), `clrthreads`, `dso`/`dumpstackobjects`, `finalizequeue`, `gchandles`, `analyzeoom`, `eeheap`, `dumpconcurrentqueue/dictionary`.

## 4) ThreadPool starvation (oficial: *Debug ThreadPool starvation*, .NET 9+)
- **Definição:** o pool não tem threads livres para os itens enfileirados ⇒ respostas lentas. Sintoma na doc: sob carga, a latência fica muito acima da latência normal (3,48 s e 15,42 s contra ~500 ms nos exemplos).
- **Detectar com `dotnet-counters monitor -n <app>`:** `dotnet.thread_pool.thread.count` **sobe rápido para 2–3× o número de núcleos e depois +1–2 threads/s** até estabilizar bem acima (ex.: >125); `dotnet.thread_pool.queue.length` alta; `dotnet.thread_pool.work_item.count`. **Estabilizar em valor alto (mais de ~3× os núcleos) normalmente indica código bloqueando threads do pool** e o pool compensando.
- A partir do .NET 6 a heurística escala mais rápido para certas APIs bloqueantes (`Task.Wait`/`Result`), tornando a starvation mais curta, mas **ela ainda ocorre**.
- **Descobrir o que bloqueia:**
  - Problema **contínuo:** `dotnet-stack report -n <app>` imprime stacks de todas as threads; procure muitas threads em `ManualResetEventSlim.Wait` → `Task.SpinThenBlockingWait` → `Task.GetResultCore` chamadas do seu método, com base `ThreadPoolWorkQueue.Dispatch`/`WorkerThreadStart` (= são threads do pool).
  - Problema **intermitente:** `dotnet-trace collect -n <app> --clrevents waithandle --clreventlevel verbose --duration 00:00:30` (evento **WaitHandleWait**, .NET 9+, emitido quando a thread bloqueia por `Task.Result/Wait/GetAwaiter().GetResult()`, `lock`, `Monitor.Enter`, `ManualResetEventSlim`…); analise no PerfView.
- **Correção oficial:** não bloquear threads do pool — usar **async/await** de ponta a ponta (a doc mostra a latência voltando a ~500 ms e menos threads). Ver `csharp-async-await`. Gerar carga para reproduzir: a doc usa Bombardier (ferramenta de terceiros).

## 5) Crash e StackOverflow
- **Dump em crash** por variáveis de ambiente (definidas **antes** de iniciar o processo): `DOTNET_DbgEnableMiniDump=1` (padrão 0); `DOTNET_DbgMiniDumpType` (1 `Mini`, **2 `Heap` — padrão**, 3 `Triage` sem dados pessoais, 4 `Full`); `DOTNET_DbgMiniDumpName` (caminho; padrão `/tmp/coredump.<pid>`; aceita `%p` PID, `%e` executável, `%h` host, `%t` tempo; o usuário do processo precisa ter permissão de escrita); `DOTNET_CreateDumpDiagnostics=1` (log do createdump); `DOTNET_EnableCrashReport=1` (relatório JSON de threads/frames, não suportado no Windows). Single-file e Native AOT só suportam dump `Full`. Não aplicável a Android/iOS.
- **StackOverflow:** o processo termina com "Stack overflow." e frames repetidos; muitas vezes só o log já mostra o método recursivo. Para aprofundar no Linux: `DOTNET_DbgEnableMiniDump=1`, `dotnet-sos install`, abrir o core no **lldb** (`bt`) e usar SOS `ip2md <endereço>` no frame repetido; no Windows, Visual Studio mostra a exceção e a pilha.
- `dotnet-dump collect` serve quando o app **ainda não crashou** (ex.: travado); dump em crash não ajuda nesse caso.

## Ferramentas — referência rápida
| Ferramenta | Uso | Notas oficiais |
|---|---|---|
| `dotnet-counters` | `monitor` (ao vivo) e `collect --format csv|json -o` (para arquivo); padrão `System.Runtime` | Pode iniciar o app (`-- <comando>`) para ver métricas de startup; usa a primeira app .NET que conectar. |
| `dotnet-dump` | `collect` (`--type Full|Heap|Mini|Triage`; **padrão Full**; `-o`), `analyze` (SOS; `-c` para comandos em lote), `ps` | Não precisa de debugger nativo (útil em Alpine, sem lldb). **Dump Full/Heap pode fazer o SO paginar muita memória**; em container com limite, pode matar o container. |
| `dotnet-gcdump` | Grafo de heap de processo vivo | Abre só em PerfView/VS no Windows. |
| `dotnet-trace` | `collect` / `collect-linux`, perfis, providers | `--stopping-event-*` para parar ao ver um evento. |
| `dotnet-stack` | `report` (stacks de todas as threads) | Usa EventPipe; leve. |
| `dotnet-monitor` | Agente para produção: coleta **dumps, traces, logs e métricas** sob demanda ou por regras automáticas; imagem `mcr.microsoft.com/dotnet/monitor`; API HTTP em `https://localhost:52323`, `/metrics` na porta 52325 | **`--no-auth` é fortemente desaconselhado em produção.** Ideal para múltiplas réplicas (dumps remotos/por gatilho). |
| `dotnet-symbol` | Baixa símbolos/DAC para abrir dump de outra máquina | |
| `dotnet-sos` / `dotnet-debugger-extensions` | Instala SOS (lldb/WinDbg) | |
| `PerfCollect` | Script Linux (perf + LTTng) | Em container exige capabilities (`PERFMON`, `SYS_PTRACE`; às vezes `SYS_ADMIN`) e `DOTNET_PerfMapEnabled=1`, `DOTNET_EnableEventLog=1` no alvo. |

## Métricas de runtime (para o 1º passo)
- **Meter `System.Runtime`** (automático em todo app **.NET 9+**): `dotnet.process.cpu.time`, `dotnet.process.memory.working_set`, `dotnet.gc.collections`, `dotnet.gc.heap.total_allocated`, `dotnet.gc.last_collection.heap.size` / `.fragmentation.size` / `.memory.committed_size`, `dotnet.gc.pause.time`, `dotnet.jit.*`, `dotnet.thread_pool.thread.count` / `.work_item.count` / `.queue.length`, `dotnet.monitor.lock_contentions`, `dotnet.timer.count`, `dotnet.assembly.count`, `dotnet.exceptions`.
- **.NET anterior ao 9** (ou apps que usam EventCounters): nomes antigos como `gc-heap-size`, `threadpool-thread-count`, `threadpool-queue-length`, `exception-count`, `cpu-usage`, `monitor-lock-contention-count`, `alloc-rate`, `working-set` (referência *Available counters*). A UI do `dotnet-counters` também é diferente antes do .NET 9.
- Métricas do ASP.NET Core/Kestrel (`http.server.request.duration` etc.): `dotnet-observability`.

## Containers (oficial: *Collect diagnostics in Linux containers*)
- As ferramentas funcionam **dentro do mesmo container**, **no host** ou em **sidecar**. Dentro do container ficam sujeitas aos limites de recursos (dump/gcdump consomem memória e disco; trace/counters também podem sofrer); `dotnet-dump` usa um processo auxiliar com **ptrace**; instalar as ferramentas na imagem aumenta tamanho e superfície de ataque (ou baixe sob demanda).
- **Sidecar/host:** os containers precisam **compartilhar o process namespace** e o **`/tmp`** (onde o runtime cria o socket Unix do *diagnostic port*, p.ex. via volume); alternativa: `--diagnostic-port <caminho>` mapeando o `/tmp` do alvo. O **caminho de saída do dump é interpretado no sistema de arquivos do processo alvo**, não do sidecar. Mesmo de fora, o alvo pode consumir mais memória ao gerar o dump.
- **Dump falha no Linux/containers** (FAQ): o `createdump` usa `ptrace()` e lê `/proc`; erro típico `[createdump] ... open(/proc/<pid>/mem) FAILED Permission denied`. Causas: perfil **seccomp** que bloqueia `ptrace` (Docker só permite com kernel > 4.8 ou capability **`CAP_SYS_PTRACE`**), usuário diferente sem `CAP_SYS_PTRACE`, processo não "dumpable", ou LSM (Yama `ptrace_scope` 2/3 nega; SELinux/AppArmor). Verifique `cat /sys/kernel/security/lsm` e `cat /proc/sys/kernel/yama/ptrace_scope`. No macOS, o host precisa de entitlements.
- **Limite de memória e GC:** em container com limite, o GC trata o limite como memória total; `GCHeapHardLimit` padrão é o maior entre 20 MB e `GCHeapHardLimitPercent` (padrão **75%**) do limite. Ver `dotnet-memory-disposable` e `aspnet-hosting-deployment`.

## Checklist de revisão do diagnóstico
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Conclusão tirada sem confirmar o sintoma com métricas | Alta |
| 2 | Dump coletado em produção sem considerar dados sensíveis, espaço em disco e limite de memória do container | Alta |
| 3 | `dotnet-monitor` exposto sem autenticação (`--no-auth`) | Alta |
| 4 | Nome de métrica do .NET 9+ procurado em app mais antigo (ou vice-versa) | Média |
| 5 | Só um dump para suspeita de vazamento (sem comparação no tempo) | Média |
| 6 | Starvation tratada sem remover o bloqueio sync-over-async (a correção oficial é async/await) | Média |
| 7 | Variáveis de crash dump definidas depois do processo iniciar | Média |
| 8 | Ferramenta rodando com usuário/`TMPDIR` diferente do alvo (timeout) | Baixa |
| 9 | Perfil de trace pesado deixado ligado em produção | Média |
| 10 | Sem política de retenção/descarte dos artefatos coletados | Média |

## Fontes oficiais
- Diagnostics in .NET (visão geral): https://learn.microsoft.com/en-us/dotnet/core/diagnostics/
- Ferramentas: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/tools-overview
- Debug a memory leak: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/debug-memory-leak
- Debug high CPU usage: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/debug-highcpu
- Debug a deadlock: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/debug-deadlock
- Debug ThreadPool starvation: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/debug-threadpool-starvation
- Debug a StackOverflow: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/debug-stackoverflow
- Dumps: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dumps
- Coletar dumps em crash: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/collect-dumps-crash
- FAQ de dumps: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/faq-dumps
- dotnet-counters: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-counters
- dotnet-dump: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-dump
- dotnet-gcdump: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-gcdump
- dotnet-trace: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-trace
- dotnet-stack: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-stack
- dotnet-monitor: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-monitor
- Diagnóstico em containers: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/diagnostics-in-containers
- Métricas de runtime: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/built-in-metrics-runtime
- EventCounters conhecidos: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/available-counters
- Configuração do GC (heap hard limit): https://learn.microsoft.com/en-us/dotnet/core/runtime-config/garbage-collector
