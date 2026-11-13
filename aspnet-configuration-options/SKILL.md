---
name: aspnet-configuration-options
description: Implementar e revisar configuração e Options pattern no .NET/ASP.NET Core - IConfiguration, appsettings.json por ambiente, precedência de provedores, variáveis de ambiente (__), user secrets, binding, IOptions/IOptionsSnapshot/IOptionsMonitor, validação (ValidateDataAnnotations, ValidateOnStart, IValidateOptions), named options. Use quando o usuário pedir para ler configurações, criar classe de Options, validar configuração ou revisar onde ficam segredos. Based on official Microsoft Learn docs.
---

# Configuração e Options pattern

Só afirmar o que a doc oficial diz (fontes no fim). Connection strings/segredos de banco: `efcore-dbcontext-connection`.

## Configuração (`IConfiguration`)
- Fornece visão única de várias **fontes** (JSON, env vars, linha de comando, secrets...). É **somente leitura** (não é feita para escrita). Valores são **strings**; `null` não pode ser armazenado nem bindado.
- Hierarquia por chaves com **`:`** (`Logging:LogLevel:Default`); em variáveis de ambiente use **`__`** (`Logging__LogLevel__Default`). `:` é reservado: não use em chaves de dicionário bindado (use outro delimitador/workaround).
- **Precedência padrão** (maior → menor, `WebApplication.CreateBuilder`): (1) argumentos de linha de comando, (2) variáveis de ambiente (sem prefixo `ASPNETCORE_`/`DOTNET_`), (3) **user secrets** (só em Development), (4) `appsettings.{ENVIRONMENT}.json`, (5) `appsettings.json`, (6) configuração de host de fallback. Se a mesma chave existe em vários provedores, **vale o último adicionado**. Segredos em user secrets vencem o `appsettings`.
- Acesse via `builder.Configuration` (não chame `CreateBuilder` de novo só para ler config). Evite `IConfiguration` crua espalhada: **prefira o Options pattern** quando a configuração cresce.
- Em apps de console o .NET não expõe configuração por padrão (adicione `Microsoft.Extensions.Configuration`); o Generic Host (`Microsoft.Extensions.Hosting`) é recomendado quando também há DI/logging.
- Providers com recarga (arquivos) permitem mudar valores sem reiniciar; mudanças só chegam via `IOptionsSnapshot`/`IOptionsMonitor`.

## Segredos (doc)
- **Nunca** senhas/dados sensíveis em código de provider ou arquivo de configuração em texto puro.
- Em desenvolvimento use **Secret Manager** (`dotnet user-secrets`); **não use segredos de produção em dev/test**; guarde segredos **fora do projeto** para não irem ao repositório; produção: Key Vault/variáveis de ambiente e o fluxo de autenticação mais seguro disponível.

## Binding
- Binder converte seções em objetos; usa `TypeConverter` se existir (o binder source-generated não). Propriedades com **setter privado** ou tipo não convertível são **ignoradas**. Não faz binding direto em `IReadOnlyList<T>`/`IReadOnlyDictionary`: use tipo mutável na propriedade e exponha como read-only. Construtor parametrizado: só se houver **um único** construtor público parametrizado.
- A chave da seção **não precisa** casar com o nome da classe (`"FaultHandling"` → `TransientFaultHandlingOptions`).

## Options pattern
Classe de options: **não abstrata, com construtor público sem parâmetros**, propriedades com setter; uma por cenário (ISP/encapsulamento: o consumidor depende só do que usa).
```csharp
public sealed class SettingsOptions
{
    public const string SectionName = "MyCustomSettingsSection";
    [Required] public required string SiteTitle { get; set; }
    [Range(0, 1_000, ErrorMessage = "Value for {0} must be between {1} and {2}.")] public required int Scale { get; set; }
}

builder.Services
    .AddOptions<SettingsOptions>()
    .Bind(builder.Configuration.GetSection(SettingsOptions.SectionName))
    .ValidateDataAnnotations()      // pacote Microsoft.Extensions.Options.DataAnnotations
    .ValidateOnStart();             // valida na inicialização, não no primeiro uso
```
| Interface | Lifetime | Recarrega após iniciar | Named | Observação |
|---|---|---|---|---|
| `IOptions<T>` | Singleton (injetável em qualquer lifetime) | **Não** | Não | valor avaliado no `.Value` |
| `IOptionsSnapshot<T>` | **Scoped** (não pode ir em Singleton) | Sim, por requisição/escopo | Sim | recalculada a cada resolução em scoped/transient |
| `IOptionsMonitor<T>` | Singleton (qualquer lifetime) | Sim, com **notificações de mudança** (`OnChange`) | Sim | só para providers baseados em arquivo; cache invalidável (`IOptionsMonitorCache`) |
- `IConfigureOptions`/`IPostConfigureOptions` (post roda depois de todas as configurações). Todas as options são "nomeadas"; o nome padrão é `string.Empty`; `IConfigureNamedOptions` para instâncias nomeadas; `OptionsBuilder<T>` simplifica nomeadas e validação.
- **Configure com serviços da DI** via overloads do `OptionsBuilder` (não chame `BuildServiceProvider`).
- **Validação:** `ValidateDataAnnotations()`, `.Validate(delegate)`, `IValidateOptions<T>` (classe para validação complexa), e **source generator de validação em tempo de compilação** (`ValidateObjectMembers`, `ValidateEnumeratedItems`) para desempenho. Falha lança `OptionsValidationException` (`ex.Failures`). Por padrão a validação ocorre em runtime no acesso; use `ValidateOnStart` para falhar cedo.
- Autores de biblioteca: ver "Options pattern guidance for library authors".

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Config tipada via Options, não `configuration["a:b"]` espalhado |
| 2 | Options class concreta, ctor público sem parâmetros, `required`/validação |
| 3 | `ValidateOnStart` para configuração crítica |
| 4 | `IOptionsSnapshot` não injetado em singleton; `IOptionsMonitor` onde precisa reagir a mudanças |
| 5 | Segredos fora de `appsettings.json` versionado (user-secrets/env/Key Vault) |
| 6 | Convenção `__` em variáveis de ambiente; precedência entendida (env sobrescreve JSON) |
| 7 | `BuildServiceProvider` chamado para ler config/options durante o registro |
| 8 | Binding em `IReadOnly*`/setters privados esperando que funcionem |

## Fontes oficiais
- Configuration in ASP.NET Core: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/
- Configuration in .NET: https://learn.microsoft.com/en-us/dotnet/core/extensions/configuration
- Options pattern: https://learn.microsoft.com/en-us/dotnet/core/extensions/options
- Options para autores de bibliotecas: https://learn.microsoft.com/en-us/dotnet/core/extensions/options-library-authors
- Safe storage of app secrets (Secret Manager): https://learn.microsoft.com/en-us/aspnet/core/security/app-secrets
