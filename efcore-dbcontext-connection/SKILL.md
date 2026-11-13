---
name: efcore-dbcontext-connection
description: Configurar e revisar a conexão com banco de dados e o DbContext no EF Core / ASP.NET Core (AddDbContext, UseSqlServer/UseNpgsql/UseSqlite, connection string via configuration, tempo de vida scoped, DbContextOptions, AddDbContextFactory, thread safety, retry/resiliência, SaveChangesAsync). Use quando o usuário perguntar como conectar com o banco, registrar o DbContext ou revisar uso do contexto. Based on official Microsoft Learn docs.
---

# EF Core — DbContext e conexão com o banco

Só afirmar o que a doc oficial diz (fontes no fim).

## Onde guardar a connection string (doc "Connection Strings")
A connection string pode conter informação sensível e muda entre ambientes. O ASP.NET Core Configuration permite guardá-la em: `appsettings.json`/`appsettings.Development.json`, **variável de ambiente**, **Azure Key Vault** ou **Secret Manager** (`dotnet user-secrets`). **Segredos nunca devem ir para arquivos de configuração versionados.**
```json
{ "ConnectionStrings": { "BloggingDatabase": "Server=(localdb)\\mssqllocaldb;Database=...;Trusted_Connection=True;" } }
```
```bash
dotnet user-secrets init
dotnet user-secrets set ConnectionStrings:DefaultConnection "<sua connection string>"
```
`GetConnectionString("X")` lê a chave `ConnectionStrings:X` (precisa de `Microsoft.Extensions.Configuration`). A doc avisa que os exemplos usam banco local sem autenticação: em produção use o **fluxo de autenticação mais seguro disponível** (ver "Secure authentication flows"). Em WinForms/WPF/ASP.NET 4 o padrão é `App.config`/`Web.config` (proteger seções com dados sensíveis); em UWP/SQLite local a string costuma ficar no código.

## Como conectar (ASP.NET Core)

```csharp
var connectionString =
    builder.Configuration.GetConnectionString("DefaultConnection")
        ?? throw new InvalidOperationException("Connection string 'DefaultConnection' not found.");

builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(connectionString));

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options) { }
}
```
- `AddDbContext` registra o contexto como **scoped** → uma instância por requisição HTTP = uma *unit of work*.
- O contexto precisa de **construtor público** com `DbContextOptions<TContext>` (é assim que a config chega).
- Injete por construtor (`ApplicationDbContext context`) em controllers/services.

## Providers (exigem o pacote NuGet correspondente)
| Banco | Config | Pacote |
|---|---|---|
| SQL Server / Azure SQL | `UseSqlServer(cs)` | Microsoft.EntityFrameworkCore.SqlServer |
| SQLite | `UseSqlite(cs)` | Microsoft.EntityFrameworkCore.Sqlite |
| PostgreSQL* | `UseNpgsql(cs)` | Npgsql.EntityFrameworkCore.PostgreSQL |
| MySQL/MariaDB* | `UseMySql(cs)` | Pomelo.EntityFrameworkCore.MySql |
| Cosmos DB | `UseCosmos(cs, db)` | Microsoft.EntityFrameworkCore.Cosmos |
| In-memory | `UseInMemoryDatabase(name)` | Microsoft.EntityFrameworkCore.InMemory |
\* provedores não mantidos pela Microsoft. **In-memory não é para produção** e a doc de testes do EF Core **desencoraja** seu uso até para testes (ver `efcore-testing`).
Se o compilador não achar `UseX`, falta o pacote ou `using Microsoft.EntityFrameworkCore;`. Cada instância usa **um** provider.

Resiliência (Azure SQL): `options.UseSqlServer(cs, o => o.EnableRetryOnFailure())`.

## Regras da doc sobre o DbContext
1. Vida curta: uma unit of work (criar → rastrear entidades → alterar → `SaveChanges(Async)` → descartar). **Descarte sempre** (libera recursos e evita vazamento por eventos).
2. **Não é thread-safe.** Não compartilhe entre threads nem rode operações paralelas na mesma instância; **`await` todas as chamadas async imediatamente**. Erro típico: `InvalidOperationException` "A second operation started on this context...". Sem detecção → corrupção de dados.
3. Para paralelismo: um contexto por thread (escopo via `IServiceScopeFactory`) ou registrar como transient.
4. `InvalidOperationException` lançada pelo EF pode deixar o contexto em estado irrecuperável (erro de programação).
5. **`AddDbContextFactory` / `IDbContextFactory<T>`** quando não há escopo alinhado (ex.: Blazor Server) ou há várias units of work no mesmo escopo. Contextos criados pela factory **não** são gerenciados pelo DI: você descarta (`using var context = factory.CreateDbContext()`).
6. Use `DbContextOptions<TContext>` (genérico). Classe não herdável: `sealed`. Se for base herdada: construtor `protected` com `DbContextOptions` não genérico.
7. Opções úteis: `UseQueryTrackingBehavior`, `LogTo`, `EnableSensitiveDataLogging` (só dev), `EnableDetailedErrors`.
8. `new DbContext` manual com `OnConfiguring` e string literal é válido, mas **strings hardcoded** de exemplo não servem para produção.
9. Ferramentas de design (migrations) precisam conseguir criar o contexto; ver "Design-time context creation".
10. Sempre use as APIs assíncronas (`SaveChangesAsync`, `ToListAsync`); misturar sync/async pode causar starvation do thread pool.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Connection string lida da configuração (não hardcoded; segredos fora do repositório) |
| 2 | `AddDbContext` com provider certo e pacote instalado |
| 3 | Contexto scoped; nenhum `static`/singleton guardando DbContext |
| 4 | Sem `new Context()` em endpoints/services (use DI ou factory + `using`) |
| 5 | Sem chamadas EF paralelas na mesma instância (`Task.WhenAll` com o mesmo contexto) |
| 6 | Todas as chamadas async aguardadas (`await`) |
| 7 | InMemory fora de protótipo descartável (para testes, a doc desencoraja: ver `efcore-testing`) |
| 8 | `EnableSensitiveDataLogging` fora de produção |
| 9 | Retry/resiliência para bancos em nuvem |
| 10 | Contexto não vaza para fora da camada de dados (DTOs na API) |

## Fontes oficiais
- DbContext lifetime, configuration: https://learn.microsoft.com/en-us/ef/core/dbcontext-configuration/
- Connection strings: https://learn.microsoft.com/en-us/ef/core/miscellaneous/connection-strings
- Database providers: https://learn.microsoft.com/en-us/ef/core/providers/
- Connection resiliency: https://learn.microsoft.com/en-us/ef/core/miscellaneous/connection-resiliency
- Testing code that uses EF Core: https://learn.microsoft.com/en-us/ef/core/testing/
