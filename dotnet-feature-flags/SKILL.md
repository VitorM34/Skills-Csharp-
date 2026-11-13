---
name: dotnet-feature-flags
description: Implementar e revisar feature flags em .NET/ASP.NET Core com Microsoft.FeatureManagement - declaração em appsettings (feature_management), IVariantFeatureManager, FeatureGate, filtros (Percentage, TimeWindow, Targeting, customizados), rollout progressivo, variantes/A-B, telemetria, snapshot por requisição, integração com Azure App Configuration e Minimal APIs, ciclo de vida das flags e testes. Use quando o usuário pedir feature flag, toggle, rollout gradual, canary, kill switch, A/B test, ou ao revisar esse código.
---

# Feature flags com Microsoft.FeatureManagement

**Proveniência:** (1) documentação **oficial Microsoft** no Learn — *.NET feature management* (`feature-management-dotnet-reference`), *Feature management overview* (`concept-feature-management`), quickstart ASP.NET Core de App Configuration e how-to de telemetria — marcada **[MS]**; (2) **código-fonte** do repositório `microsoft/FeatureManagement-Dotnet` (inclusive `WithFeatureGate` para Minimal APIs, que **não aparece na página de referência que li**) marcado **[SRC]**. **CONVENÇÃO** = recomendação desta skill, não da doc. **Não li:** schema JSON completo (`FeatureManagement.v2.0.0`), recorrência detalhada do TimeWindow (apenas o essencial), o pacote `Microsoft.FeatureManagement.Telemetry.OpenTelemetry` (só o README do repo), How-to de variantes específicas de App Configuration, preços/limites do Azure App Configuration, e produtos de terceiros (LaunchDarkly, Unleash, OpenFeature). Versões no NuGet (out/2026): `Microsoft.FeatureManagement` e `.AspNetCore` **4.8.0**.
Ligações: `aspnet-configuration-options`, `aspnet-minimal-api`, `aspnet-mvc-controllers-filters`, `aspnet-razor-pages`, `aspnet-blazor`, `dotnet-dependency-injection`, `dotnet-observability`, `aspnet-health-checks`, `dotnet-unit-testing`, `dotnet-integration-testing`, `dotnet-security-review`, `aspnet-web-security`, `dotnet-feature-workflow`.

## Quando usar / não usar (CONVENÇÃO)
Flags separam **liberar** de **fazer deploy** [MS]. Casos: *kill switch*/toggle operacional, rollout gradual/canário, acesso por grupo/usuário, janela de tempo, A/B (variantes). **Não** use flag para: autorização (flag ≠ permissão — use `aspnet-authentication-authorization`), configuração comum (`IOptions`), nem como substituta de branch longa que ninguém remove.

## Declaração (appsettings) [MS]
```json
{
  "feature_management": {
    "feature_flags": [
      { "id": "NewCheckout", "enabled": true },
      { "id": "Beta", "enabled": true,
        "conditions": { "client_filters": [
          { "name": "Microsoft.Percentage", "parameters": { "Value": 20 } } ] } }
    ]
  }
}
```
- Seção padrão: `feature_management` (ou a antiga `FeatureManagement`); outra seção via `AddFeatureManagement(configuration.GetSection("MyFlags"))`. Se `feature_management` e `FeatureManagement` declaram a mesma flag, vale a de `feature_management`. Schema novo (v2) é obrigatório para **variantes e telemetria** (a partir da 4.0).
- Semântica: `enabled:false` → desligada. `enabled:true` **sem** `conditions` → ligada. Com `conditions` → ligada só se os filtros decidirem. Filtros são percorridos até um dizer "ligada" (`requirement_type` padrão `Any`); com `All`, **todos** precisam passar — e `All` sem filtros = **desligada**.
- O caractere `:` é proibido no nome da flag. Nomes são strings mágicas: centralize em constantes (`public static class Flags { public const string NewCheckout = nameof(NewCheckout); }`) (CONVENÇÃO).
- Várias fontes de configuração com a mesma flag: o merge padrão do .NET une arrays **por índice** (resultado inesperado); desde a **4.3.0** dá para ligar `ConfigurationFeatureDefinitionProviderOptions.CustomConfigurationMergingEnabled = true` (último vence).

## Registro e consumo [MS]
```csharp
builder.Services.AddFeatureManagement();           // singletons; lê IConfiguration
// builder.Services.AddScopedFeatureManagement();  // se filtros usam serviços scoped; Blazor Server (scoped)

public class CheckoutService(IVariantFeatureManager features)
{
    public async Task RunAsync(CancellationToken ct)
    {
        if (await features.IsEnabledAsync(Flags.NewCheckout, ct)) { /* novo */ } else { /* antigo */ }
    }
}
```
- A doc usa **`IVariantFeatureManager`** (v4; implementa o que `IFeatureManager` fazia + variantes). O código ainda expõe `IFeatureManager` (`IsEnabledAsync(string)` e com contexto) — para código novo siga a doc.
- **Estado muda em runtime** (vem do `IConfiguration`, que "providers cuidam de cache/atualização"). Para estado **consistente durante uma requisição**, injete **`IVariantFeatureManagerSnapshot`**: cacheia a primeira avaliação da requisição. Recomendado quando o mesmo fluxo consulta a mesma flag mais de uma vez (CONVENÇÃO).
- Filtros disponíveis **sem** pacote extra de código: registrados automaticamente (`PercentageFilter`, `TimeWindowFilter`, `ContextualTargetingFilter`); `TargetingFilter` precisa de `.WithTargeting()`.

## ASP.NET Core (`Microsoft.FeatureManagement.AspNetCore`) [MS]
- **MVC/Razor Pages**: `[FeatureGate("X")]` no controller/action (404 por padrão via `IDisabledFeaturesHandler`, substituível); em Razor Pages vai **no tipo da página, não no handler method**. Filtros MVC condicionais: `o.Filters.AddForFeature<MeuFiltro>("X")` (somente `IAsyncActionFilter`).
- **Views**: `<feature name="X">…</feature>` (`negate="true"`, `requirement`, variantes via `variant=`); precisa de `@addTagHelper *, Microsoft.FeatureManagement.AspNetCore` no `_ViewImports.cshtml`.
- **Middleware**: `app.UseMiddlewareForFeature<T>("X")` / `app.UseForFeature(name, ab => …)` — o pipeline pode mudar em runtime.
- **Minimal APIs [SRC]**: `app.MapGet(...).WithFeatureGate("X")` (`IEndpointConventionBuilder`; sobrecargas com `RequirementType` e `negate`). Não li a página de docs que o cita — confira na versão instalada.
- Filtro que lê o request: injete `IHttpContextAccessor` (`services.AddHttpContextAccessor()`).

## Filtros customizados [MS]
```csharp
[FilterAlias("Browser")]                       // nome usado no JSON; padrão = tipo sem o sufixo "Filter"
public class BrowserFilter(IHttpContextAccessor http) : IFeatureFilter
{
    public Task<bool> EvaluateAsync(FeatureFilterEvaluationContext ctx)
    {
        var s = ctx.Parameters.Get<BrowserFilterSettings>() ?? new();   // parâmetros do JSON
        return Task.FromResult(/* decidir com base em http.HttpContext e s */ false);
    }
}
builder.Services.AddFeatureManagement().AddFeatureFilter<BrowserFilter>();
```
- Filtro **não registrado** referenciado numa flag → **exceção** na avaliação; `FeatureManagementOptions.IgnoreMissingFeatureFilters = true` desliga (cuidado: pode mascarar erro de nome — CONVENÇÃO).
- Filtros contextuais (`IContextualFeatureFilter<T>`): passe o contexto em `IsEnabledAsync(feature, context)`; úteis fora de HTTP (console, workers).
- Filtro que faz I/O roda a **cada avaliação** — mantenha rápido ou cacheie (CONVENÇÃO).
- Fonte de flags própria (banco/serviço): implemente `IFeatureDefinitionProvider` e registre antes de `AddFeatureManagement()`.

## Filtros embutidos [MS]
- `Microsoft.Percentage` (`Value`): habilita a feature por percentual. A doc que li **não diz** se o resultado é estável por usuário; para rollout por usuário/grupo com percentual a doc descreve o filtro **Targeting** (abaixo).
- `Microsoft.TimeWindow` (`Start`/`End` no formato dos exemplos, ex.: `Sun, 01 Jun 2025 13:59:59 GMT`; só `Start` = ligada depois; só `End` = até; `Recurrence` exige `Start` e `End`, e o `End` define a *duração*).
- `Microsoft.Targeting`: `Audience` com `Users`, `Groups` (cada um com `RolloutPercentage`), `DefaultRolloutPercentage` e `Exclusion`. Ordem: excluído → desligada; senão ligada se está em `Users`, ou no percentual de algum grupo, ou no percentual padrão; senão desligada.
  ```csharp
  builder.Services.AddFeatureManagement().WithTargeting();   // ou WithTargeting<MeuAccessor>()
  ```
  O accessor padrão do pacote AspNetCore usa `HttpContext.User`: `UserId` = `Identity.Name`, `Groups` = claims `Role`. Para outro critério, implemente `ITargetingContextAccessor`. `TargetingEvaluationOptions.IgnoreCase` ajusta comparação. Em console: `ContextualTargetingFilter` com `TargetingContext { UserId, Groups }` passado em `IsEnabledAsync`.
- **Rollout progressivo** (padrão da doc): usuários específicos → grupo/anel (20% → 100%) → % da base → 100%. Combine com telemetria para decidir avanço.

## Variantes (A/B) [MS]
- Variante = valor da flag (string/número/bool/objeto de configuração). `Variant v = await features.GetVariantAsync("Flag", ct);` → `v.Name`, `v.Configuration` (`IConfigurationSection`, pode ser bindada). Alocação via `allocation` (`default_when_enabled`, `default_when_disabled`, `user`, `group`, `percentile`). `status_override` (`None`/`Enabled`/`Disabled`) deixa a variante forçar o estado; **não** sobrescreve flag com `enabled:false`. Há também injeção de serviço por variante (`[VariantServiceAlias]`, não li em detalhe).
- Variantes exigem o schema `feature_management` (v2) e, para A/B de verdade, telemetria.

## Telemetria [MS]
- Por padrão **não** emite. Ative por flag: `"telemetry": { "enabled": true, "metadata": {…} }`. A biblioteca usa `ActivitySource` chamado **`Microsoft.FeatureManagement`** e adiciona `ActivityEvent` `FeatureFlag` com tags do schema `FeatureEvaluationEvent`; consuma com `ActivityListener` ou pacote de publicação. Application Insights: `.AddApplicationInsightsTelemetry()` no builder + `app.UseMiddleware<TargetingHttpContextMiddleware>()` para guardar o contexto de targeting na atividade.
- OpenTelemetry: pacote `Microsoft.FeatureManagement.Telemetry.OpenTelemetry` (`AddFeatureManagementProcessors()` no builder de `AddOpenTelemetry()`, registrado antes dos exporters — README do repo; detalhes não li). Ligação com `dotnet-observability`.
- **Privacidade**: o targeting grava `UserId` nos eventos — confira LGPD/GDPR (`dotnet-security-review`).

## Azure App Configuration (opcional) [MS]
- `builder.Configuration.AddAzureAppConfiguration(o => { o.Connect(new Uri(endpoint), new DefaultAzureCredential()); o.UseFeatureFlags(); })` + `services.AddAzureAppConfiguration()` + `services.AddFeatureManagement()` (+ middleware de refresh `app.UseAzureAppConfiguration()` conforme a doc de dinamicidade). Entra ID é o recomendado ao invés de connection string; `UseFeatureFlags()` carrega flags sem label; intervalo de refresh padrão **30 s** (`CacheExpirationInterval`). Escolhas de limites/preço **não li**.
- Alternativas: appsettings (a doc diz que o `IConfiguration` provider cuida de cache/atualização; se muda sem reiniciar depende do provider — não li os detalhes do provider de arquivo), banco via `IFeatureDefinitionProvider`, serviços de terceiros (não li).

## Ciclo de vida e higiene (CONVENÇÃO)
- Toda flag nasce com **dono, objetivo e data de remoção**; flag de release é temporária — remova código morto e a definição após 100%. Flags permanentes são só operacionais (kill switch).
- Evite aninhar/combinar muitas flags (explosão de caminhos); teste os dois lados (ligada/desligada).
- **Falha segura**: decida o comportamento quando a fonte de flags está indisponível/ausente (a doc só afirma que, sem a seção `feature_management`/`FeatureManagement`, a configuração é considerada **vazia**; o resultado de `IsEnabledAsync` para uma flag inexistente **não li** — teste).
- Mudanças de flag em produção são mudanças de produção: auditoria/quem alterou, aprovação, e observabilidade antes/depois.
- Flag em frente a migração de banco: aplique o padrão expand/contract (`efcore-migrations-modeling`), nunca dependa de flag para esconder schema incompatível.

## Testes (CONVENÇÃO)
- Unit: injete um `IVariantFeatureManager` falso/ stub (a interface é pequena) ou construa um `ConfigurationBuilder().AddInMemoryCollection` com `feature_management:feature_flags:0:id`… e `AddFeatureManagement()` real, para cobrir seu filtro de ponta a ponta.
- Integração: `WebApplicationFactory` com `ConfigureAppConfiguration` ligando/desligando a flag (`dotnet-integration-testing`); teste ambos os caminhos e o 404 do `FeatureGate`.

## Checklist de revisão
- [ ] Flag declarada no schema `feature_management`; semântica `enabled`/`conditions`/`requirement_type` correta (All sem filtros = desligada).
- [ ] Nomes de flag em constantes; sem `:` no nome.
- [ ] Uso de `IVariantFeatureManager` (ou `Snapshot` quando precisa de consistência na requisição); `CancellationToken` repassado.
- [ ] `[FeatureGate]` em Razor Pages no tipo da página; Minimal API com `WithFeatureGate`; comportamento de desabilitado (404) é o desejado.
- [ ] Filtros customizados registrados (`AddFeatureFilter`), com alias correto; `IgnoreMissingFeatureFilters` não usado para esconder erro.
- [ ] Targeting com `ITargetingContextAccessor` adequado (usuário/grupos); rollout progressivo planejado; Percentage não usado quando precisa de consistência por usuário.
- [ ] Telemetria habilitada por flag onde houver experimento; dados pessoais no evento avaliados.
- [ ] Flag **não** substitui autorização; segurança não depende de flag no cliente.
- [ ] Dono + data de remoção por flag; código/definições mortas removidos; testes cobrem on/off.
- [ ] Fonte de flags: refresh/cache conhecido (App Configuration 30 s por padrão); falha segura definida.

## Fontes
- [MS] https://learn.microsoft.com/azure/azure-app-configuration/feature-management-dotnet-reference ; https://learn.microsoft.com/azure/azure-app-configuration/concept-feature-management ; https://learn.microsoft.com/azure/azure-app-configuration/quickstart-feature-flag-aspnet-core ; how-to de telemetria ASP.NET Core (`how-to-telemetry-aspnet-core`) — repo `MicrosoftDocs/azure-docs`, `articles/azure-app-configuration`.
- [SRC] https://github.com/microsoft/FeatureManagement-Dotnet (README, `src/Microsoft.FeatureManagement.AspNetCore`, `IFeatureManager.cs`).
