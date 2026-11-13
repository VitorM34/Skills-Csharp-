---
name: dotnet-test-automation
description: Estratégia e automação de testes em .NET - tipos de teste (unitário, integração, carga), escolher framework (xUnit, MSTest, NUnit, TUnit) e plataforma (VSTest vs Microsoft.Testing.Platform), estrutura de projetos de teste, dotnet test, filtros (--filter), cobertura de código (Coverlet, ReportGenerator), CI. Use quando o usuário pedir testes automatizados, estruturar a suíte de testes, rodar/filtrar testes na linha de comando ou configurar cobertura/CI. Based on official Microsoft Learn docs.
---

# Testes automatizados em .NET — estratégia, ferramentas e execução

Só afirmar o que a doc oficial diz (fontes no fim). Escrever teste unitário: `dotnet-unit-testing`. Integração ASP.NET Core: `dotnet-integration-testing`. EF Core: `efcore-testing`.

## 1. Tipos de teste (doc "Testing in .NET")
| Tipo | O que testa | Observações da doc |
|---|---|---|
| **Unitário** | componente/método isolado ("unit of work"); só código sob seu controle | **Não** testa infraestrutura (banco, arquivos, rede) |
| **Integração** | dois ou mais componentes funcionando juntos; amplitude maior; frequentemente com infraestrutura real | mais código, mais lento; limite aos cenários de infraestrutura mais importantes |
| **Carga** | se o sistema suporta uma carga (usuários concorrentes, responsividade) | ver "ASP.NET Core load/stress testing" (não lido; consultar antes de detalhar) |
Regra da doc de integração: **se um comportamento pode ser testado com unitário ou integração, escolha o unitário.** TDD (escrever o teste antes) é citado como prática que ajuda a produzir código mais simples.

## 2. Plataforma × framework
- **Framework de teste** = o que você escreve (atributos/APIs): **MSTest**, **NUnit**, **xUnit.net**, **TUnit**. **Plataforma** = quem executa e integra com IDE/CLI: **VSTest** ou **Microsoft.Testing.Platform (MTP)**.
- MSTest, NUnit e xUnit suportam VSTest e MTP; **TUnit só MTP**.
- Escolha **uma plataforma por repositório**; **não misture** projetos VSTest e MTP na mesma solution/execução (não suportado).
- MTP quando: Native AOT/trimming, testes que se comportam como executáveis (`dotnet run`, `dotnet watch`), defaults estritos/determinísticos (ex.: falhar se nenhum teste rodar), WinUI/UWP (versões específicas). VSTest quando: mistura com adaptadores não-.NET (C++/JS) ou integrações antigas de CI/ferramentas.
- `dotnet test` tem dois modos: **VSTest** (padrão; único antes do .NET 10 SDK) e **MTP** (a partir do .NET 10 SDK, só para apps MTP). Rodar MTP em modo VSTest (`TestingPlatformDotnetTestSupport=true` + `Microsoft.Testing.Platform.MSBuild`) é considerado legado e será removido na MTP v2 com .NET 10 SDK. Defina propriedades da plataforma em `Directory.Build.props` para não divergir entre projetos.
- Relatórios TRX no MTP exigem a extensão `Microsoft.Testing.Extensions.TrxReport` (senão exit code 5).

## 3. Estrutura da solution (tutorial xUnit + integração)
```
solution.sln
  src/MyApp/                       (ou PrimeService/)   código sob teste
  tests/MyApp.UnitTests/           dotnet new xunit; referencia MyApp
  tests/MyApp.IntegrationTests/    Microsoft.AspNetCore.Mvc.Testing; SDK Web
```
- **Projetos separados para unitários e de integração** (doc de integração): evita que componentes de infraestrutura entrem nos unitários e permite escolher qual conjunto rodar.
- Criação: `dotnet new sln`, `dotnet new classlib`, `dotnet new xunit -o X.Tests`, `dotnet sln add`, `dotnet add <teste> reference <código>`.

## 4. Executar
```bash
dotnet test                                   # todos os projetos de teste da solution
dotnet test --filter "FullyQualifiedName~UnitTests"
dotnet test --filter "FullyQualifiedName\!~IntegrationTests"   # exclui (escape do ! em shells Linux/macOS)
```
Filtro (`--filter <Propriedade><Operador><Valor>`): operadores `=` , `!=`, `~` (contém), `!~`; combine com `|` (ou) e `&` (e), parênteses permitidos; valor sem operador = `FullyQualifiedName~valor`; buscas **case-insensitive**. Propriedades: MSTest (`FullyQualifiedName`, `Name`, `ClassName`, `Priority`, `TestCategory`, `Id`); xUnit (`FullyQualifiedName`, `DisplayName`, `Traits`); NUnit (`FullyQualifiedName`, `Name`, `Priority`, `TestCategory`, `Category`, `Property`). Escapes: `\(`, `\)`, `\&`, `\|`, `\=`, `\!`, `\~`, `\\`; vírgula em genéricos = `%2C`; **aspas no valor inteiro** quando contiver `< > ,` (obrigatório no PowerShell). Com `vstest.console.exe` use `--testcasefilter:`.
Usar traits/categorias (ex.: separar `Category=Integration`) permite rodar subconjuntos em pipelines.

## 5. Cobertura (doc "Use code coverage for unit testing")
- Cobertura = quanto do código (linhas, branches, métodos) é executado pelos testes. Duas famílias: **data collectors** (coletam durante a execução) e **report generators** (geram relatório legível).
- Opções: coletor **embutido** do .NET (`--collect:"Code Coverage"`, arquivo binário `.coverage`; converter com `dotnet-coverage`), ou **Coverlet** (open source; `--collect:"XPlat Code Coverage"` gera `coverage.cobertura.xml` em `TestResults`; o template do xUnit já traz `coverlet.collector`). **ReportGenerator** converte Cobertura em HTML.
```bash
dotnet test --collect:"XPlat Code Coverage"
```
- Cobertura alta **não** prova qualidade, e metas muito ambiciosas (ex.: 95%) podem ser contraproducentes (ver `dotnet-unit-testing`).

## 6. Pipeline (CI)
`dotnet test` é multiplataforma e serve em CI/CD e scripts. Rode unitários em todo commit/PR; integração conforme custo (filtro ou job separado). Azure DevOps: tarefa `DotNetCoreCLI@2` (`dotnet test`) funciona com VSTest e MTP; a `VSTest@3` só com VSTest. Para providers e bancos em CI, ver `efcore-testing` (Docker/Testcontainers citados pela doc).


## 7. Mais recursos documentados
### NUnit
A Microsoft documenta NUnit por tutorial (`dotnet new nunit`: SDK de teste + framework NUnit + adaptador) e pela página *MTP support in NUnit (NUnit runner)*. Atributos/asserts de NUnit: consulte nunit.org (não há referência de API na doc da Microsoft). Filtro `dotnet test --filter` suporta as propriedades `Category`, `Property`, `Priority`, `TestCategory`, `Name`, `FullyQualifiedName`.

### Microsoft.Testing.Platform: extensões (todas via pacote NuGet; auto-registradas com `Microsoft.Testing.Platform.MSBuild`)
| Necessidade | Extensão / opção |
|---|---|
| Cobertura | `Microsoft.Testing.Extensions.CodeCoverage`: `--coverage`, `--coverage-output`, `--coverage-output-format coverage|xml|cobertura`, `--coverage-settings`. No MTP o padrão `IncludeTestAssembly` é `false` (no VSTest era `true`). A partir da MTP 2.4: limites (thresholds) de cobertura; falha de limite sai com **exit code 14** (`--ignore-exit-code 14` para ignorar) |
| Relatórios | TRX (`--report-trx`, pacote `Microsoft.Testing.Extensions.TrxReport`), Azure DevOps, GitHub Actions (log groups/annotations/job summary), HTML, JUnit, CTRF; `--results-directory`; `--report-*-filename` com placeholders `{asm}`, `{tfm}`, `{arch}`, `{pname}`, `{pid}`, `{time}`; relatório com o mesmo nome é **sobrescrito** (use `{time}` para manter histórico); consolidação de relatórios (MTP 2.4, experimental) |
| Repetir testes instáveis | `Microsoft.Testing.Extensions.Retry`: `--retry-failed-tests N`, `--retry-failed-tests-max-percentage`, `--retry-failed-tests-max-tests`, `--retry-failed-tests-delay` (MTP 2.3+). Indicado para **testes de integração** com falhas transitórias, **não** para esconder testes instáveis (a MTP 2.4 reporta contagens `flaky`/`retried`). Licença restritiva do pacote |
| Diagnóstico | dumps de crash/hang, gravação de tela (experimental), OpenTelemetry |
| Dev loop | Hot Reload, Microsoft Fakes |
| Outros | saída de terminal customizável, server mode (integração com IDE), carregamento dinâmico de extensões |
Opção `--help` do executável de teste (ou `dotnet test --help` no modo MTP) lista o que está registrado; opção de extensão não instalada é "não reconhecida". Se desligar o entry point gerado (`GenerateTestingPlatformEntryPoint=false`), registre as extensões manualmente no `Main` (`builder.AddTrxReportProvider()` etc.; TRX por último).
**Princípios da MTP:** determinismo (sem reflexão para coordenar a execução), transparência de runtime (sem AppDomain/AssemblyLoadContext), registro de extensões em compilação, zero dependências, hostável.

### Ordem de execução
A doc diz que **idealmente a ordem não deve importar** e é boa prática evitá-la. Se for preciso: MSTest (ordem de definição ou `OrderTestsByNameInClass`), e ordenar não equivale a desativar paralelismo (para garantir execução serial, desative também). Alternativa: playlists do Visual Studio.

### Teste de mutação (Stryker.NET)
`dotnet tool install -g dotnet-stryker`; rode `dotnet stryker` no diretório do projeto de testes. Stryker faz **mutações** deliberadas no código (ex.: `price <= 0` → `price < 0`, `+` → `-`, strings, etc.) e roda os testes: mutante **morto** (testes falharam) = bom; **sobrevivente** = testes fracos. Relatório HTML em `StrykerOutput`. Mede a **qualidade** dos testes, mais que a cobertura.

### Testes de carga e estresse (ASP.NET Core)
- **Carga:** a app aguenta a carga especificada de usuários mantendo a meta de resposta, em condições normais. **Estresse:** estabilidade sob condições extremas (picos, carga crescente, recursos limitados) e capacidade de **se recuperar** da falha.
- Faça em **Release/Production**, não em Debug/Development (Development liga logs mais verbosos que afetam desempenho).
- Ferramentas citadas: **Azure Load Testing** (serviço gerenciado, usa scripts Apache JMeter), JMeter, ApacheBench, Gatling, jmeter-dotnet-dsl, k6, Locust, West Wind WebSurge, Netling, Vegeta, NBomber (C#/F#). Load testing do Visual Studio 2019 está **descontinuado** e o serviço de carga do Azure DevOps foi encerrado.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Há pirâmide razoável: muitos unitários, integração focada nos pontos de infraestrutura |
| 2 | Unitários e integração em projetos separados |
| 3 | Uma só plataforma (VSTest **ou** MTP) em toda a solution; propriedades em `Directory.Build.props` |
| 4 | Framework consistente na solution; pacotes do template (`Microsoft.NET.Test.Sdk`, runner) presentes |
| 5 | Testes rodam com `dotnet test` sem depender de IDE/máquina local |
| 6 | Testes de integração distinguíveis por filtro/trait |
| 7 | Cobertura configurada e usada como indicador, não como meta única |
| 8 | CI executa os testes e publica resultados/cobertura |
| 9 | Sem testes dependentes de ordem, de relógio ou de dados compartilhados |
| 10 | Nenhum teste "ignorado" sem motivo documentado |
| 11 | Testes instáveis tratados na causa; `retry` só para falhas transitórias de integração |
| 12 | Carga/estresse rodados em Release com ferramenta adequada |

## Fontes oficiais
- Testing in .NET (visão geral): https://learn.microsoft.com/en-us/dotnet/core/testing/
- Test platforms (VSTest × MTP): https://learn.microsoft.com/en-us/dotnet/core/testing/test-platforms-overview
- Testing with `dotnet test`: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-with-dotnet-test
- Run selected unit tests (filtros): https://learn.microsoft.com/en-us/dotnet/core/testing/selective-unit-tests
- Code coverage: https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-code-coverage
- Unit testing C# com xUnit (tutorial): https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-csharp-with-xunit
- Integration tests ASP.NET Core: https://learn.microsoft.com/en-us/aspnet/core/test/integration-tests
- Load/stress testing: https://learn.microsoft.com/en-us/aspnet/core/test/load-tests
