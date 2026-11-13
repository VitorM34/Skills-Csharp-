---
name: dotnet-native-aot-trimming
description: Decidir, habilitar e revisar Native AOT (PublishAot) e trimming (PublishTrimmed) em .NET/ASP.NET Core - benefícios e limitações, compatibilidade de recursos do ASP.NET Core (Minimal APIs parcial, MVC/Blazor Server não), template webapiaot e CreateSlimBuilder, EF Core (experimental, não recomendado em produção), warnings IL2xxx/IL3xxx e como corrigir (DynamicallyAccessedMembers, RequiresDynamicCode), source generators (System.Text.Json, configuration binding), otimização de tamanho, diagnóstico limitado, segurança, containers e cross-compile. Use quando o usuário quiser reduzir startup/memória/tamanho, publicar como binário nativo, ou tratar warnings de trim/AOT. Based on official Microsoft Learn docs (.NET 10 / ASP.NET Core 10 / EF Core).
---

# Native AOT e trimming

Só afirmar o que a doc oficial diz (fontes no fim). Relacionadas: `aspnet-minimal-api`, `dotnet-json-serialization`, `aspnet-configuration-options`, `aspnet-hosting-deployment`, `dotnet-observability`, `dotnet-production-diagnostics`, `dotnet-project-tooling`, `efcore-sql-performance`, `dotnet-ci-cd`.

## O que é e quando vale a pena
- **Native AOT** (`PublishAot`): o app é **self-contained e compilado antecipadamente para código nativo**; **não usa JIT** em execução; roda sem runtime instalado e em ambientes onde JIT é proibido. Benefícios documentados: **menor tamanho em disco** (imagens menores, deploy mais rápido), **menor tempo de startup**, **menor uso de memória** (depende do trabalho do app). A doc diz que o ganho é **mais significativo em cargas com muitas instâncias** (infraestrutura de nuvem, hiperescala).
- **Trimming** (`PublishTrimmed`): remove código não usado de apps **self-contained**; totalmente suportado desde o .NET 6; **só para self-contained**. Native AOT **implica trimming** e compilação em arquivo único.
- **Custo:** o app precisa ser **analisável em tempo de build**. Reflexão irrestrita, plugins, geração de código em runtime e vários frameworks **não funcionam**. Se o projeto depende disso, a resposta honesta é **não usar AOT**.

## Limitações oficiais do Native AOT
Sem carregamento dinâmico (`Assembly.LoadFile`); sem geração de código em runtime (`System.Reflection.Emit`); sem C++/CLI; Windows: sem COM embutido; exige trimming (e suas [incompatibilidades](#incompatibilidades-de-trimming)); implica arquivo único; inclui as bibliotecas de runtime necessárias (maior que framework-dependent); **`System.Linq.Expressions` sempre interpretado** (mais lento); genéricos com **struct** como argumento têm **todas as instanciações pré-geradas** (pode inflar o tamanho); nem toda a biblioteca de runtime está anotada (alguns warnings não são acionáveis); diagnóstico limitado; suporte parcial a recursos do ASP.NET Core. Um binário gerado no Linux só roda na **mesma versão ou mais nova** do Linux (ex.: gerado no Ubuntu 20.04 não roda no 18.04). Alvos: Windows/Linux/macOS (x64, Arm64; .NET 9+ inclui Windows x86 e Linux Arm); iOS/tvOS/MacCatalyst/Android têm páginas próprias.

## Habilitar e publicar
- `.csproj`: `<PublishAot>true</PublishAot>` (**no projeto, não só na linha de comando**: ele também habilita a **análise de código dinâmico no build e na edição**). Publicar: `dotnet publish -r <RID> -c Release` (ex.: `linux-x64`, `win-x64`).
- **Pré-requisitos de build:** Windows = Visual Studio com workload C++ (Desktop development with C++); Linux = toolchain (`clang` + `zlib1g-dev` no Ubuntu; `clang build-base zlib-dev` no Alpine; `clang zlib-devel` em Fedora/RHEL); macOS = Xcode Command Line Tools.
- **`dotnet build`/`run`/`test` usam o runtime completo (CoreCLR)**; só **`publish`** gera o binário nativo. Com `PublishAot` presente o **comportamento deve ser o mesmo** (features incompatíveis ficam desabilitadas e lançam exceção em runtime; analyzer destaca o código incompatível). A doc recomenda **desenvolver/depurar/testar normalmente e publicar AOT como um dos últimos passos**, mas também **publicar com frequência para descobrir problemas cedo**.
- **Cross-compile:** **não há suporte cross-OS** (precisa VM/WSL); **cross-arquitetura** (x64↔arm64) é suportado com a toolchain nativa do alvo instalada (Linux: cross-linker como `clang`, `objcopy`/`strip` do alvo se `StripSymbols`, objetos do C runtime e zlib do alvo).
- **Símbolos:** o publish gera arquivo separado (`.dbg` Linux, `.pdb` Windows, `.dSYM` macOS), **necessário para depurar e analisar dumps**; em Unix `StripSymbols=false` embute no binário (maior).

## Compatibilidade com ASP.NET Core (doc *ASP.NET Core support for Native AOT*)
| Recurso | Status |
|---|---|
| Minimal APIs | **parcial** |
| gRPC, CORS, HealthChecks, HttpLogging, **JWT Authentication**, Localization, OutputCaching, RateLimiting, RequestDecompression, ResponseCaching, ResponseCompression, Rewrite, StaticFiles, WebSockets | ✔ suportado |
| SignalR | **parcial** |
| **MVC (controllers)**, **Blazor Server**, **OData**, **outras autenticações** (além de JWT), **Session**, **Spa** | ❌ **não suportado** |
- Tipos de app suportados (.NET 8+): **Minimal APIs, gRPC, Worker services**. Se o projeto usa controllers/MVC ⇒ **não é candidato** a AOT (`aspnet-controllers`).
- Um app com **AOT warnings no publish pode não funcionar corretamente**; **sem warnings** é esperado que funcione igual ao JIT. Teste o binário AOT de verdade.
- **Template `webapiaot`:** só Minimal APIs; usa **`WebApplication.CreateSlimBuilder`**; escuta **só HTTP** (HTTPS normalmente fica no ingress/proxy); sem perfil IIS; JSON com **source generator**; sample Todo.
- **`CreateSlimBuilder` x `CreateBuilder`:** mantém `appsettings*.json`, user secrets, logging no console e configuração de logging; **não** tem: hosting startup assemblies, `UseStartup`, provedores de log **EventLog, Debug e EventSource**, `UseStaticWebAssets`, integração IIS, **endpoints HTTPS e QUIC/HTTP3 no Kestrel** (habilite com `UseKestrelHttpsConfiguration` / `UseQuic`), constraints de rota regex e alpha. `WebApplication.CreateEmptyBuilder` omite tudo.

## JSON e outras fontes de reflexão
- **System.Text.Json:** por padrão usa reflexão ⇒ **quebra em AOT**. Use **source generation**: classe `partial : JsonSerializerContext` com `[JsonSerializable(typeof(T))]` e registre com `builder.Services.ConfigureHttpJsonOptions(o => o.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonSerializerContext.Default))`. **Todos os tipos enviados no corpo ou retornados por delegates de Minimal API devem estar no contexto**; parâmetros que não vêm do corpo (ex.: query `IParsable<T>`) não precisam. Defina **`<JsonSerializerIsReflectionEnabledByDefault>false</JsonSerializerIsReflectionEnabledByDefault>`** para falhar cedo e de forma previsível (com `PublishTrimmed`, a reflexão já vem desabilitada se você não definir). Ver `dotnet-json-serialization`.
- **Configuração:** `<EnableConfigurationBindingGenerator>true</EnableConfigurationBindingGenerator>` (.NET 8+) gera o binding por **interceptors** (C# 12) sem reflexão (`ConfigurationBinder`, `Configure<T>`/`Bind`) — ver `aspnet-configuration-options`.
- Para inspecionar código gerado: `<EmitCompilerGeneratedFiles>true</EmitCompilerGeneratedFiles>` (saída em `obj/.../generated/`).
- Bibliotecas que usam reflexão, carregamento condicional ou geração de código em runtime **precisam de atualização**; verifique se a dependência é compatível antes de escolher AOT.

## Warnings: como tratar (docs *Fix trim warnings* / *Introduction to AOT warnings*)
- **Regra oficial:** "um app que usa trimming/AOT **não deve produzir nenhum warning**"; se houver, teste exaustivamente e confirme que não há mudança de comportamento. Analyzers: `EnableTrimAnalyzer`, `EnableAotAnalyzer`, `EnableSingleFileAnalyzer`.
- **Ordem de abordagem (oficial):** (1) **eliminar a reflexão** (genéricos em tempo de compilação no lugar de `Type`/`Activator.CreateInstance`; **source generators**); (2) **`[DynamicallyAccessedMembers(...)]`** quando os tipos são conhecidos (anote o parâmetro/retorno/genérico que satisfaz a reflexão, ex.: `PublicMethods`); (3) **`[RequiresUnreferencedCode]` / `[RequiresDynamicCode]`** quando é realmente dinâmico (documenta a incompatibilidade; os chamadores recebem o warning); (4) **suprimir só em último caso**, com `[UnconditionalSuppressMessage]` + `Justification`, quando você tem certeza de que é seguro (ex.: protegido por `RuntimeFeature.IsDynamicCodeSupported`).
- Códigos frequentes: **IL2026** (membro com `RequiresUnreferencedCode`), **IL2067/IL2070/IL2075/IL2087** (argumento/`this`/retorno/genérico não satisfaz `DynamicallyAccessedMembers`), **IL3050** (membro com `RequiresDynamicCode`, ex.: `MakeGenericType`), IL3051 (consistência de `RequiresDynamicCode` em virtual/interface), IL3052 (COM), IL3053 (assembly produziu warnings AOT), IL3054 (recursão genérica), IL3055 (P/Invoke com delegate abstrato), IL3058 (assembly referenciado sem anotação AOT). Suprima códigos via `NoWarn`/`WarningsAsErrors`/`TreatWarningsAsErrors`; para tratar só os do trimmer como erro há opção própria.
- Mensagens de erro de AOT em runtime existem **porque o native code daquela instanciação não foi gerado**: o publish precisa listar tudo em build time.

## Incompatibilidades de trimming
Serializers baseados em reflexão (**Newtonsoft.Json** → System.Text.Json com source generation; `ConfigurationManager` → configuration binding generator; **BinaryFormatter** → migrar), **`Reflection.Emit`**, **carregamento dinâmico de assemblies/plugins**, C++/CLI, COM embutido (→ COM Wrappers), **WPF** e **Windows Forms** (trimming desabilitado pelo SDK), XML serialization legado. Recursos desabilitados em apps trimmed por padrão: `BuiltInComInteropSupport`, `CustomResourceTypesSupport`, `EnableCppCLIHostActivation`, `StartupHookSupport` etc.

## Otimização de tamanho/velocidade (doc *Optimize AOT deployments* + *Trimming options*)
- `<OptimizationPreference>Size|Speed</OptimizationPreference>` (padrão = blend rápido-mas-atento-ao-tamanho).
- Propriedades de **feature switches** que removem código (**trade-off de funcionalidade**): `InvariantGlobalization=true` (remove dados de globalização — ver impacto em cultura), `UseSystemResourceKeys=true` (mensagens de exceção do `System.*` viram IDs), `StackTraceSupport=false` (sem stack traces do runtime), `EventSourceSupport=false`, `MetricsSupport=false`, `DebuggerSupport=false` (também remove símbolos), `HttpActivityPropagationSupport=false`, `Http3Support=false` (.NET 10+), `MetadataUpdaterSupport=false`, `XmlResolverIsNetworkingEnabledByDefault=false`; `UseSizeOptimizedLinq` (.NET 10+) é **true por padrão com `PublishAot`**.
- ⚠ **Desligar `EventSourceSupport`, `MetricsSupport`, `StackTraceSupport` prejudica observabilidade/diagnóstico** (`dotnet-observability`, `dotnet-production-diagnostics`): decida conscientemente.

## Diagnóstico em AOT (doc *Diagnostics and instrumentation*)
- **Observabilidade/telemetria: suporte parcial.** **EventPipe é suportado** (base de logging/tracing, **OpenTelemetry**, `dotnet-trace`/`dotnet-counters`), mas **exige `EventSourceSupport=true`**; nem todos os runtime events/providers existem.
- **Debug:** o debugger **gerenciado não funciona** no binário publicado; use debuggers **nativos** (WinDbg/VS, gdb/lldb) com o **arquivo de símbolos**; para exceções gerenciadas, breakpoint em **`RhThrowEx`** (a exceção está no 1º registrador: `rcx` x64 / `x0` Arm64). **Dump:** a doc diz que no .NET 8 envolve passos manuais.
- **CPU profiling:** parcial (PerfView, perf). **Análise de heap gerenciado: NÃO suportada** (a tabela da doc marca como não suportado; o texto cita `dotnet-gcdump`, PerfView e ferramentas do Visual Studio como não funcionando no .NET 8 — confirme se mudou na sua versão). Ver `dotnet-production-diagnostics` — as receitas de memory leak com `dumpheap`/`gcdump` **não se aplicam** a AOT; reproduza o problema no CoreCLR.

## EF Core com Native AOT — **experimental**
- A doc do EF (9.0, sem mudança de status encontrada nas novidades do 10) diz: NativeAOT e **query precompilation** são **"altamente experimentais, ainda não adequados para produção"** e **recomenda contra publicar apps EF com NativeAOT em produção**; a publicação ainda emite warnings de trim/AOT.
- Funcionamento: pacote `Microsoft.EntityFrameworkCore.Tasks` + `PublishAot` + `<InterceptorsNamespaces>...Microsoft.EntityFrameworkCore.GeneratedInterceptors</InterceptorsNamespaces>` (interceptors são experimentais); o publish gera o modelo compilado e interceptors com o SQL final. `dotnet ef dbcontext optimize --precompile-queries --nativeaot` gera sem publicar. Qualquer mudança no código invalida os interceptors (faça no pipeline de publicação).
- **Limitações:** **queries dinâmicas** (compostas por `if`/variável entre statements) **não são suportadas** (reescreva como queries estáticas distintas); **sintaxe de query expression do LINQ não suportada**; value converters com estado capturado não; modelo/interceptors gerados podem ser grandes e lentos; **o provider precisa suportar** query precompilation. **Alternativa:** `dotnet ef dbcontext optimize --precompile-queries` **sem NativeAOT** reduz o startup mantendo queries dinâmicas.
- Conclusão para a skill: **app com EF Core em produção ⇒ não use Native AOT** (segundo a doc atual). Ver `efcore-sql-performance`.

## Segurança (doc *Security features*)
Sem geração de código em runtime (permite assinar todo o código executável e rodar em ambientes que proíbem páginas executáveis novas); **superfície de reflexão restrita**; **Control Flow Guard** no Windows (`<ControlFlowGuard>Guard</ControlFlowGuard>`); **CET Shadow Stack** habilitado por padrão ao publicar para Windows (.NET 9+; desabilite com `CetCompat=false`).

## Containers e CI
- O **sample oficial** usa imagem de build `sdk` com `clang zlib1g-dev` instalados e imagem final **`runtime-deps`** (sem runtime .NET), copiando o binário publicado; gere o binário numa distro **igual ou mais antiga** que a de execução (binário só roda na mesma versão ou mais nova). (A doc aponta os Dockerfiles Linux/Windows do repositório `dotnet/samples`; o exemplo lido usa tags 8.0 — troque pela versão do seu alvo.) Uso conjunto com `dotnet publish /t:PublishContainer`: **não verificado nas páginas lidas**.
- No CI: publique o **binário AOT** (`dotnet publish -r <rid>`) e **rode os testes contra ele** quando possível; falhe o build em warnings IL2xxx/IL3xxx (`dotnet-ci-cd`, `TreatWarningsAsErrors`).

## Bibliotecas
Marque `IsAotCompatible=true` (habilita `IsTrimmable`, `EnableTrimAnalyzer`, `EnableSingleFileAnalyzer`, `EnableAotAnalyzer`); mire **net8.0 ou superior** (mínimo para análise AOT) e, se multi-target com `netstandard2.0`/`net472`, inclua `net8.0` e condicione com `IsTargetFrameworkCompatible`. `VerifyReferenceAotCompatibility=true` avisa (IL3058) de referências sem a metadata `IsAotCompatible` (introduzida no .NET 10; opt-in porque pode ser ruidoso). Publicar uma biblioteca como Native AOT gera **shared library** nativa expondo métodos `[UnmanagedCallersOnly(EntryPoint=...)]` (bibliotecas estáticas e `dlclose`/`FreeLibrary` não são suportados). P/Invoke: ligação preguiçosa por padrão; `DirectPInvoke` gera chamadas diretas.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Projeto com controllers/MVC, Blazor Server, OData, Session ou autenticação não-JWT escolhendo AOT | Alta |
| 2 | Publicar com warnings IL2xxx/IL3xxx e assumir que funciona | Alta |
| 3 | `System.Text.Json` sem `JsonSerializerContext` / tipos de body/retorno fora do contexto; reflexão não desabilitada | Alta |
| 4 | Newtonsoft/BinaryFormatter/`Reflection.Emit`/plugins dinâmicos/`Assembly.LoadFile` no código ou em dependências | Alta |
| 5 | EF Core com Native AOT em produção (experimental) ou queries dinâmicas com precompilation | Alta |
| 6 | Supressões (`UnconditionalSuppressMessage`) sem justificativa; `RequiresUnreferencedCode` espalhado para silenciar warnings | Média |
| 7 | Feature switches de tamanho que quebram observabilidade (`EventSourceSupport`, `MetricsSupport`, `StackTraceSupport`) ou globalização (`InvariantGlobalization`) sem decisão consciente | Média |
| 8 | Plano de diagnóstico ignorando que debugger gerenciado e análise de heap não funcionam em AOT; símbolos (`.dbg/.pdb`) não guardados | Média |
| 9 | Esperar HTTPS/HTTP3 do `CreateSlimBuilder` sem configurar (ou sem proxy de TLS) | Média |
| 10 | Binário gerado em distro mais nova que o ambiente de execução; cross-OS tentado | Média |
| 11 | Benefício não medido (startup/memória/tamanho) — AOT adotado por moda | Baixa |
| 12 | Biblioteca própria sem `IsAotCompatible` consumida por app AOT | Média |

## Fontes oficiais
- Native AOT deployment: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/
- Optimize AOT deployments: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/optimizing
- Diagnostics (AOT): https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/diagnostics
- Security features (AOT): https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/security
- Cross-compilation: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/cross-compile
- Native interop (AOT): https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/interop
- Building native libraries: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/libraries
- Introduction to AOT warnings: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/fixing-warnings
- IL3050: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/warnings/il3050
- Trim self-contained deployments: https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/trim-self-contained
- Fix trim warnings: https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/fixing-warnings
- Trimming options: https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/trimming-options
- Known trimming incompatibilities: https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/incompatibilities
- Prepare libraries for trimming: https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/prepare-libraries-for-trimming
- ASP.NET Core support for Native AOT: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/native-aot
- EF Core — NativeAOT and precompiled queries: https://learn.microsoft.com/en-us/ef/core/performance/nativeaot-and-precompiled-queries
- System.Text.Json source generation: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/source-generation
- Configuration source generator: https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration-generator
