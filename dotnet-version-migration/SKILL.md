---
name: dotnet-version-migration
description: Planejar e revisar upgrade de versão do .NET/ASP.NET Core/EF Core (8→9→10) e portar de .NET Framework - passos oficiais (global.json, TFM, pacotes), breaking changes por versão (ASP.NET Core, EF Core, bibliotecas core, containers), warnings de obsolescência (ASPDEPR), .NET Upgrade Assistant, política de suporte (LTS/STS), roll-forward, e checklist de verificação pós-upgrade. Use quando o usuário pedir "atualizar para .NET 10", migrar de net8/net9, tratar warnings/breaking changes após upgrade ou revisar um PR de migração. Based on official Microsoft Learn docs. Cobre .NET 8, 9 e 10; .NET 11 é preview e não está incluído.
---

# Migração de versão do .NET

Só afirmar o que a doc oficial diz (fontes no fim). **Sempre consulte a lista oficial de breaking changes da versão de origem até a de destino** (não só a do destino) e confira a página atual: a doc avisa que a lista de .NET 10 "é um trabalho em andamento / não completa". Tooling de projeto: `dotnet-project-tooling`. EF: `efcore-migrations-modeling`. Deploy: `aspnet-hosting-deployment`. Testes: `dotnet-test-automation`.

## Decisão: qual versão alvo
- Suporte (doc *Releases and support*): **.NET 10 = LTS até nov/2028**; **.NET 9 = STS até nov/2026**; **.NET 8 = LTS até nov/2026**. Após o fim do suporte não há patches de segurança ⇒ planeje a migração antes. Major pode trazer breaking changes; **patches** mensais (2ª terça) mantêm compatibilidade; apps não sobem de major automaticamente (roll-forward só de minor/patch por padrão).

## Procedimento oficial ASP.NET Core 9→10 (aplica-se igual em outros saltos, trocando números)
1. **Ler** os breaking changes (abaixo) e as *what's new*.
2. **`global.json`**: atualizar `sdk.version` para o SDK 10 instalado (ex.: `10.0.100`). Ver `dotnet-project-tooling` (rollForward).
3. **TFM**: `<TargetFramework>net10.0</TargetFramework>` em todos os projetos.
4. **Pacotes**: atualizar `Microsoft.AspNetCore.*`, `Microsoft.EntityFrameworkCore.*`, `Microsoft.Extensions.*` e `System.Net.Http.Json` para `10.0.x` (a doc mostra o diff); pacotes de terceiros: checar compatibilidade (ver Central Package Management em `dotnet-project-tooling`).
5. **Blazor**: ver a seção própria do guia de migração.
6. Build, **tratar warnings novos** (ASPDEPR…, CA…), rodar testes e validar em ambiente real.
- Tooling auxiliar: **.NET Upgrade Assistant** (Visual Studio ou CLI) **analisa** o código e gera relatório de incompatibilidades, e ajuda a atualizar projetos (ASP.NET, console, bibliotecas, WPF/WinForms, MAUI…). Existe também integração com GitHub Copilot (*github-copilot-upgrade*). É ferramenta de apoio; revise o resultado.

## Breaking changes que mais afetam (oficiais)
### ASP.NET Core 10 (de 9)
| Mudança | Tipo | Ação |
|---|---|---|
| **`WithOpenApi` deprecado** (warning `ASPDEPR002`; ainda compila) | source | usar o OpenAPI nativo (`aspnet-openapi`) |
| **Cookie auth não redireciona mais para login/access-denied em endpoints de API conhecidos** (retorna 401/403; XHR já era assim) | behavioral | para restaurar: switch `Microsoft.AspNetCore.Authentication.Cookies.IgnoreRedirectMetadata` |
| **`IExceptionHandler.TryHandleAsync` retornando `true` suprime diagnósticos** (log `UnhandledException`, evento, tag `error.type` na métrica) | behavioral | opções de configuração disponíveis; ver `aspnet-error-handling`, `dotnet-observability` |
| **`WebHostBuilder`/`IWebHost`/`WebHost` obsoletos** (`ASPDEPR004`/`ASPDEPR008`) | source | migrar para `HostBuilder` ou `WebApplicationBuilder` |
| **`IPNetwork` e `ForwardedHeadersOptions.KnownNetworks` obsoletos** (`ASPDEPR005`) | source | usar `System.Net.IPNetwork` e **`KnownIPNetworks`** (`aspnet-hosting-deployment`) |
| `IActionContextAccessor`/`ActionContextAccessor` obsoletos; Razor runtime compilation obsoleto; `Microsoft.Extensions.ApiDescription.Client` deprecado; analisadores MVC API (`IncludeOpenAPIAnalyzers`) deprecados | source | ver cada página |
### ASP.NET Core 9 (de 8)
`DefaultKeyResolution.ShouldGenerateNewKey` mudou de sentido (Data Protection); **dev cert export** não cria mais pasta; **Forwarded Headers ignora `X-Forwarded-*` de proxies desconhecidos**; **HostBuilder habilita `ValidateOnBuild`/`ValidateScopes` em Development** (revela erros de DI — ver `dotnet-dependency-injection`); tipos de middleware com **múltiplos construtores** mudaram de comportamento; APIs legadas Mono/Emscripten.
### ASP.NET Core 8 (de 7)
`ConcurrencyLimiterMiddleware` obsoleto; conversores de serialização customizados removidos; **forwarded headers ignora proxies desconhecidos**; **HTTP logging requer `AddHttpLogging`**; `ISystemClock` obsoleto (use `TimeProvider`); **Minimal APIs: `IFormFile` exige antiforgery**; **rate limiting requer `AddRateLimiter`**; eventos de token retornam `JsonWebToken`; `TrimMode` padrão `full` no Web SDK.
### EF Core 10 (de 9)
**Média:** ferramentas EF exigem **`--framework`** em projetos multi-target (`dotnet ef ... --framework net9.0`). **Baixas:** SqlClient com dependência de broker; **Application Name injetado na connection string**; tipo **`json`** padrão no Azure SQL/compat. 170; **coleções parametrizadas usam vários parâmetros por padrão**; `ExecuteUpdateAsync` aceita lambda comum; **colunas de complex types com novos nomes (uniquificadas / caminho completo)** ⇒ pode gerar migration; nomes de parâmetros SQL simplificados; mudanças em APIs de convenção/logger. Teste suas migrations e consultas.
### EF Core 9 (de 8)
**Altas:** `Migrate()`/`MigrateAsync()`/`dotnet ef database update` **lançam exceção se o modelo tem mudanças pendentes** (`PendingModelChangesWarning`) — causas comuns: sem migrations, snapshot ausente, **`HasData` com valores dinâmicos (`DateTime.Now`, `Guid.NewGuid()`)** ⇒ use valores fixos ou o novo padrão de seeding, provider diferente, opções do Identity que mudam o modelo (use projeto de startup ou `IDesignTimeDbContextFactory`); **aplicar migrations dentro de transação explícita** (padrão antigo `ExecutionStrategy` + `BeginTransaction` + `Migrate`) agora **lança exceção** (o EF já abre transação e usa `ExecutionStrategy`); **todas as migrations pendentes rodam numa única transação**. **Média:** `Microsoft.EntityFrameworkCore.Design` não encontrado ao usar as ferramentas. Outras: ferramentas EF não suportam .NET Framework; `EF.Constant/Parameter` em compiled queries; coleções primitivas.
### EF Core 8 (de 7)
**Altas:** `Contains` pode não funcionar em SQL Server antigo e **pode regredir desempenho**; **enums em JSON agora são gravados como inteiros** (antes strings). **Médias:** `date`/`time` do SQL Server escaffoldam para `DateOnly`/`TimeOnly`; bool com valor gerado não vira nullable. **Baixa:** múltiplos `AddDbContext` passam a ser aplicados em ordem diferente.
### Bibliotecas core / containers do .NET 10
Entre outros (lista não exaustiva): **imagens .NET padrão passam a usar Ubuntu**; **C# 14 mudou resolução de overload com parâmetros `Span`** (`dotnet-memory-disposable`, `csharp-modern-features`); **`System.Linq.AsyncEnumerable` agora faz parte das core libraries** (source incompatible com o pacote `System.Linq.Async` — `csharp-linq`); **runtime não fornece mais handlers padrão de SIGTERM**; `ActivitySource.StartActivity` com mudança de comportamento (sampling); **propagador de trace context padrão alterado para W3C**; APIs obsoletas; `BufferedStream.WriteByte` sem flush implícito. Leia a página completa antes de decidir.

## Portar de .NET Framework (oficial, resumo)
Antes de portar: pré-requisitos (*premigration needed changes*), analisar dependências de terceiros (`third-party-deps`), usar **Upgrade Assistant**/ApiPort para relatório de portabilidade. Abordagens da doc: **deixar o compilador guiar** (projetos pequenos), ou **permanecer no .NET Framework até resolver portabilidade** (código compilando o tempo todo). ASP.NET → ASP.NET Core tem guia próprio (*fx-to-core*, migração incremental com YARP). Esta skill não cobre os detalhes.

## Checklist de revisão do PR de migração
| # | Verificar | Gravidade |
|---|---|---|
| 1 | `global.json` e TFM consistentes em todos os projetos; imagens Docker/CI no mesmo alvo | Alta |
| 2 | Pacotes `Microsoft.*` alinhados à nova versão; terceiros verificados | Alta |
| 3 | Breaking changes lidos da versão de origem até a de destino (não só a última) | Alta |
| 4 | Migrations: sem exceção de modelo pendente; sem `Migrate` dentro de transação explícita; `--framework` em multi-target | Alta |
| 5 | Comportamento de auth em APIs com cookie (401/403 vs redirect) validado | Alta |
| 6 | Forwarded headers: proxies conhecidos configurados; `KnownIPNetworks` no lugar de `KnownNetworks` | Alta |
| 7 | `ValidateOnBuild/ValidateScopes` em dev revelou erros de DI e foram corrigidos (não desligados) | Média |
| 8 | Warnings `ASPDEPR*`/`CA*` novos tratados, não suprimidos | Média |
| 9 | Exception handler/telemetria: diagnósticos esperados ainda aparecem | Média |
| 10 | Testes (unit + integração + contra banco real) e smoke em ambiente próximo de produção | Alta |
| 11 | Plano de rollback e do tempo até o fim de suporte da versão antiga | Média |

## Fontes oficiais
- Releases e suporte: https://learn.microsoft.com/en-us/dotnet/core/releases-and-support
- Migrar ASP.NET Core 9→10: https://learn.microsoft.com/en-us/aspnet/core/migration/90-to-100
- Breaking changes no .NET 10: https://learn.microsoft.com/en-us/dotnet/core/compatibility/10
- Breaking changes no ASP.NET Core 10: https://learn.microsoft.com/en-us/aspnet/core/breaking-changes/10/overview
- Breaking changes no ASP.NET Core 9: https://learn.microsoft.com/en-us/aspnet/core/breaking-changes/9/overview
- Breaking changes no ASP.NET Core 8: https://learn.microsoft.com/en-us/aspnet/core/breaking-changes/8/overview
- Breaking changes no EF Core 10: https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-10.0/breaking-changes
- Breaking changes no EF Core 9: https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-9.0/breaking-changes
- Breaking changes no EF Core 8: https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-8.0/breaking-changes
- Breaking changes (índice geral): https://learn.microsoft.com/en-us/dotnet/core/compatibility/breaking-changes
- .NET Upgrade Assistant: https://learn.microsoft.com/en-us/dotnet/core/porting/upgrade-assistant-overview
- Porting plan (.NET Framework): https://learn.microsoft.com/en-us/dotnet/core/porting/porting-approaches
- Seleção de versões/roll-forward: https://learn.microsoft.com/en-us/dotnet/core/versions/selection
