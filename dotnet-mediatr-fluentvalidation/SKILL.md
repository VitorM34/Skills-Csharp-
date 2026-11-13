---
name: dotnet-mediatr-fluentvalidation
description: Usar MediatR (mediator in-process, CQRS, pipeline behaviors, notifications, licenciamento comercial/RPL) e FluentValidation (AbstractValidator, regras, cascade, async, DI, ASP.NET Core/Minimal APIs, testes com TestValidate, upgrade para 12) corretamente em .NET. Inclui quando NÃO usar MediatR e como combinar validação com handlers. Use quando o usuário pedir CQRS, handlers, IRequest/IRequestHandler, pipeline behavior, validação com FluentValidation, ou ao revisar esse código.
---

# MediatR + FluentValidation

**Proveniência:** documentação **oficial dos projetos** (não é Microsoft): MediatR — README, wiki e fonte do repositório `LuckyPennySoftware/MediatR` (antes `jbogard/MediatR`), marcado **[MR]**; FluentValidation — `docs/` do repositório `FluentValidation/FluentValidation`, marcado **[FV]**. **CONVENÇÃO** = recomendação desta skill, não da doc (inclui a combinação MediatR + FluentValidation, que **não é documentada por nenhum dos dois**). **Não li:** termos completos da licença comercial do MediatR (o PDF/página de licença), alternativas (Mediator source generator, Wolverine, Brighter), `FluentValidation.AspNetCore` em detalhe (descontinuado), pacotes de terceiros de auto-validação/Blazor. Versões vistas no NuGet (out/2026): MediatR 14.2.0, FluentValidation 12.2.0.
Ligações: `dotnet-clean-architecture`, `dotnet-ddd-tactical`, `dotnet-messaging`, `aspnet-minimal-api`, `aspnet-mvc-controllers-filters`, `aspnet-error-handling`, `dotnet-dependency-injection`, `dotnet-xunit`, `dotnet-security-review`, `dotnet-object-mapping`, `aspnet-validation`.

## Licenciamento do MediatR — verifique ANTES de adotar [MR]
- MediatR é **dual licenciado**: **RPL 1.5** (Reciprocal Public License — exige liberar o código do software que você constrói com ele) **ou** licença comercial (Lucky Penny Software, chave de licença). O `LICENSE.md` do repo diz isso explicitamente. Para software fechado/comercial, a licença comercial é o caminho descrito pelo projeto; **eu não li os termos completos nem preços — confirme com o jurídico/na página de licença**.
- A enforcement é só por **log**: sem chave → `WARNING`; chave inválida/expirada → `ERROR`; categoria `LuckyPennySoftware.MediatR.License`. A doc afirma que não há servidor de licença, chamadas HTTP, nem degradação de features.
- Chave: `cfg.LicenseKey = "..."` no `AddMediatR`, ou `Mediator.LicenseKey` sem MS DI, ou variáveis `MEDIATR_LICENSE_KEY` / `LUCKYPENNY_LICENSE_KEY` (precedência: código > MEDIATR_ > LUCKYPENNY_). **Nunca versionar a chave** (user-secrets/variável de ambiente/secret store — `aspnet-configuration-options`). Em clientes (Blazor WASM, desktop) **não** configure a chave; silencie o log com `AddFilter("LuckyPennySoftware.MediatR.License", LogLevel.None)`.
- Validação usa `Microsoft.IdentityModel.JsonWebTokens`; versões desalinhadas de `Microsoft.IdentityModel.*` (comum com libs de auth) quebram a validação com `MissingMethodException` (doc de troubleshooting).
- Isso afeta a decisão: se licença/custo é problema, considere **não usar MediatR** (veja abaixo) — a decisão é do usuário/organização.

## Quando usar (e quando não) — CONVENÇÃO
MediatR é "uma biblioteca de baixa ambição" para **desacoplar o envio de mensagens in-process do seu tratamento** [MR]. Não é message broker nem garante entrega/persistência (`dotnet-messaging` para isso). Use quando:
- Quer handlers pequenos por caso de uso (CQRS leve) + **pipeline cross-cutting** (validação, logging, transação) uniforme.
Evite/pese quando:
- É um CRUD simples: o endpoint chamando um serviço é mais direto; o mediator acrescenta indireção (navegação de código, stack traces maiores) e uma dependência com licença.
- Quer só "chamar um método": injete o serviço/handler direto. Pipeline cross-cutting também se resolve com filtros de endpoint/middleware (`aspnet-minimal-api`, `aspnet-mvc-controllers-filters`).
- Notificações precisam ser confiáveis/duráveis: use outbox + broker (`dotnet-distributed-patterns`), não `Publish`.

## MediatR [MR]
### Mensagens e handlers
- `IRequest<TResponse>` → `IRequestHandler<TRequest,TResponse>` (**um** handler); `IRequest` (sem retorno) → `IRequestHandler<TRequest>` retornando `Task`. **A partir da v12** `IRequest` não herda mais `IRequest<Unit>` e handlers void retornam `Task` (migration guide 11→12).
- `INotification` → **zero ou mais** `INotificationHandler<T>` via `Publish`. `IStreamRequest<T>` → `IStreamRequestHandler` retornando `IAsyncEnumerable<T>` (`CreateStream`).
- Injete `ISender` (só `Send`/`CreateStream`) ou `IPublisher` em vez de `IMediator` completo quando só precisa de parte (CONVENÇÃO).
- Pacote **`MediatR.Contracts`** contém só `IRequest`, `INotification`, `IStreamRequest` — útil para contratos em projeto separado (API/gRPC/Blazor).
```csharp
public sealed record CreateOrder(Guid CustomerId, IReadOnlyList<Item> Items) : IRequest<Guid>;

public sealed class CreateOrderHandler(AppDbContext db) : IRequestHandler<CreateOrder, Guid>
{
    public async Task<Guid> Handle(CreateOrder request, CancellationToken ct)
    {
        var order = Order.Create(request.CustomerId, request.Items);
        db.Orders.Add(order);
        await db.SaveChangesAsync(ct);
        return order.Id;
    }
}
// Program.cs
builder.Services.AddMediatR(cfg =>
{
    cfg.RegisterServicesFromAssemblyContaining<Program>();
    // cfg.LicenseKey = builder.Configuration["MediatR:LicenseKey"]; // ou variável de ambiente
});
app.MapPost("/orders", async (CreateOrder cmd, ISender sender, CancellationToken ct)
    => Results.Created(..., await sender.Send(cmd, ct)));
```
Sempre repasse o `CancellationToken`.
### Registro (v12+)
- `AddMediatR` registra `IMediator`/`ISender`/`IPublisher` e **handlers como transient**, escaneando os assemblies informados. **Behaviors e pre/post processors NÃO são escaneados desde a 12.1**: registre explicitamente, **na ordem desejada** — `AddBehavior<…>()`, `AddOpenBehavior(typeof(X<,>))`, `AddStreamBehavior`, `AddRequestPreProcessor`, `AddRequestPostProcessor`. A doc diz: registre na ordem em que quer que sejam chamados.
- MS DI fecha open generics por posição: behaviors com parâmetros extras exigem a estratégia padrão do MediatR (README, "Open behaviors with nested or extra type parameters"); `CloseInContainer` **não** deve ser usado com o container da Microsoft.
- Se um handler "não é encontrado", suspeite primeiro de assembly não escaneado em `RegisterServicesFrom…` (CONVENÇÃO; não li o comportamento exato de `Send` sem handler).
### Pipeline behaviors
```csharp
public sealed class LoggingBehavior<TRequest, TResponse>(ILogger<LoggingBehavior<TRequest, TResponse>> log)
    : IPipelineBehavior<TRequest, TResponse> where TRequest : notnull
{
    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken ct)
    {
        log.LogInformation("Handling {Request}", typeof(TRequest).Name); // nunca logar o request inteiro se tiver dados sensíveis
        return await next(ct);
    }
}
```
- Behaviors só envolvem `IRequestHandler` — **não** se aplicam a `INotificationHandler`. `next` não recebe o request: dá para **mutar** o request, não **trocá-lo**. Para void, o `TResponse` do pipeline é `Unit`.
- No código atual `RequestHandlerDelegate<TResponse>` é `(CancellationToken t = default)`: repasse o token com `next(ct)` (os exemplos antigos da wiki usam `next()`).
- Existem ainda `IRequestExceptionHandler`/`IRequestExceptionAction` para tratar exceções no pipeline (README; não li os detalhes).
### Notifications
- Publisher padrão `ForeachAwaitPublisher`: executa handlers **em sequência**; pela implementação (`foreach` + `await`), uma exceção interrompe os handlers seguintes. Alternativa `TaskWhenAllPublisher`: `Task.WhenAll` (sem `Task.Run`). Customizável via `INotificationPublisher` (`cfg.NotificationPublisher`/`NotificationPublisherType`).
- `Publish` é **in-process, no mesmo fluxo da requisição**: falha de um handler falha o `Publish`. Handlers que mexem em `DbContext` compartilham escopo/transação do chamador conforme o ciclo de vida (CONVENÇÃO: defina explicitamente quem dá `SaveChanges`).
- Eventos de domínio (`dotnet-ddd-tactical`): disparar via `Publish` após persistir; confiabilidade real exige outbox.
### Boas práticas (CONVENÇÃO)
- Um handler = um caso de uso; **sem lógica de HTTP** no handler; nada de chamar `Send` dentro de handler em cadeia profunda (vira macarrão invisível).
- Requests como `record` imutáveis; não devolva entidades EF — devolva DTOs (`dotnet-dto-review`/`dotnet-object-mapping`).
- Queries: `AsNoTracking`/projeção (`efcore-querying`); commands: transação clara (behavior de transação só se for padrão consciente).
- Teste handlers diretamente (instanciando-os) e o pipeline por teste de integração (`dotnet-integration-testing`).

## FluentValidation [FV]
### Fundamentos
- Pacote `FluentValidation` (+ `FluentValidation.DependencyInjectionExtensions` para registro automático). **v12: mínimo .NET 8**, sem .NET Standard; removidos `CascadeMode` (use `ClassLevelCascadeMode`/`RuleLevelCascadeMode`), `Transform`/`TransformForEach`, `InjectValidator` (upgrade guide 12).
```csharp
public sealed class CreateOrderValidator : AbstractValidator<CreateOrder>
{
    public CreateOrderValidator()
    {
        RuleFor(x => x.CustomerId).NotEmpty();
        RuleFor(x => x.Items).NotEmpty();
        RuleForEach(x => x.Items).SetValidator(new ItemValidator());
    }
}
```
Regras ficam no **construtor**. `Validate`/`ValidateAsync` retornam `ValidationResult` (`IsValid`, `Errors`); `ValidateAndThrow` lança `ValidationException` (extensão — precisa de `using FluentValidation;`).
### Regras úteis
- **Cascade**: padrão `Continue` (roda todos os validators da regra). `Cascade(CascadeMode.Stop)` ou `RuleLevelCascadeMode = Stop` evita validators dependentes rodarem após falha (ex.: `NotNull().NotEqual(...)`). Global: `ValidatorOptions.Global.DefaultRuleLevelCascadeMode`.
- **Condições**: `When`/`Unless`/`Otherwise`. Pegadinha: por padrão a condição vale para **todos** os validators anteriores da mesma cadeia; para só o último use `ApplyConditionTo.CurrentValidator` **em cada** `When`.
- **Coleções**: `RuleForEach`, placeholder `{CollectionIndex}`; objetos complexos com `SetValidator`.
- **Custom**: `Must(...)` (preferido) ou `Custom`; torne reutilizável com método de extensão. **Assíncrono**: `MustAsync`/`CustomAsync`/`WhenAsync` e invoque com `ValidateAsync`.
- **Compor**: `Include(outroValidator)` (mesmo tipo); **RuleSets** (`RuleSet("Names", …)` + `options.IncludeRuleSets("Names")`).
- **Mensagens**: `WithMessage`, placeholders, `WithName`; **localização** segue `CurrentUICulture` (desligar: `ValidatorOptions.Global.LanguageManager.Enabled = false`).
- Dados do chamador: `ValidationContext.RootContextData`; hook `PreValidate`.
### Registro (DI)
- Registrar como **`IValidator<T>`**. `AddValidatorsFromAssemblyContaining<T>()` registra todos os validators públicos não abstratos do assembly (padrão **Scoped**; `ServiceLifetime.Transient` é a opção "mais simples e segura"; Singleton só se nada transient/scoped for injetado — a doc desaconselha para quem não domina DI). Usa reflexão (não é AOT-friendly — CONVENÇÃO; ver `dotnet-native-aot-trimming`).
### ASP.NET Core [FV]
- Abordagem recomendada pela doc: **validação manual** (injetar `IValidator<T>`, chamar `ValidateAsync`).
- Controllers: `result.AddToModelState(ModelState)` (extensão que você escreve) e devolver a view/`ValidationProblem`.
- **Minimal APIs**: validar no endpoint e responder `Results.ValidationProblem(validationResult.ToDictionary())` (`ToDictionary` desde 11.1).
- **Auto-validação via pipeline do ASP.NET (`FluentValidation.AspNetCore`) = "não recomendada para novos projetos"**: é síncrona (validators async lançam exceção), só MVC/Razor Pages, difícil de depurar; o pacote não é mais suportado. Filtro assíncrono = pacotes de terceiros (ex.: SharpGrip), que **não li**. Blazor: sem integração oficial (terceiros).
- Lado cliente: FluentValidation é só servidor.
- Comparar com validação nativa do .NET (DataAnnotations/`AddValidation` em Minimal APIs): `aspnet-minimal-api`, `aspnet-error-handling`.
### Testes [FV]
`validator.TestValidate(model)` + `ShouldHaveValidationErrorFor(x => x.Prop)` / `ShouldNotHaveValidationErrorFor` (`FluentValidation.TestHelper`; lança `ValidationTestException`). A doc recomenda tratar validators como **caixa-preta** (entrada → resultado).

## MediatR + FluentValidation juntos (CONVENÇÃO — não documentado pelos projetos)
Padrão comum: um `IPipelineBehavior` genérico que roda os `IValidator<TRequest>` antes do handler:
```csharp
public sealed class ValidationBehavior<TRequest, TResponse>(IEnumerable<IValidator<TRequest>> validators)
    : IPipelineBehavior<TRequest, TResponse> where TRequest : notnull
{
    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken ct)
    {
        if (validators.Any())
        {
            var ctx = new ValidationContext<TRequest>(request);
            var results = await Task.WhenAll(validators.Select(v => v.ValidateAsync(ctx, ct)));
            var failures = results.SelectMany(r => r.Errors).Where(f => f is not null).ToList();
            if (failures.Count != 0) throw new ValidationException(failures);
        }
        return await next(ct);
    }
}
// cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));  // registrar explicitamente (12.1+)
```
- Converta `ValidationException` em **400 + ProblemDetails** (`IExceptionHandler`/middleware — `aspnet-error-handling`), não em 500.
- Alternativa sem exceções: `Result<T>` (`dotnet-clean-architecture`). Validators async no behavior são seguros (usa-se `ValidateAsync`).
- Validação de **formato/regras de entrada** no validator; regras de **domínio/invariantes** no domínio; unicidade/concorrência exigem constraint no banco (validator não evita corrida — `efcore-saving-concurrency`).
- Validators com dependência scoped (ex.: `DbContext`) → registre Scoped/Transient; `MustAsync` com acesso a banco custa 1 query por validação.

## Checklist de revisão
- [ ] Licença do MediatR decidida e registrada (RPL vs comercial); chave fora do código; log de licença tratado.
- [ ] MediatR realmente necessário? (CRUD simples/chamada direta não precisa.)
- [ ] `AddMediatR` escaneia os assemblies certos; **behaviors/processors registrados explicitamente** e na ordem correta (12.1+).
- [ ] Handlers recebem/repassam `CancellationToken`; não retornam entidades EF; sem HTTP dentro do handler.
- [ ] `Publish` não é tratado como entrega confiável; falha de handler de notificação é considerada; outbox se precisa durabilidade.
- [ ] Validators registrados como `IValidator<T>`; lifetime Scoped/Transient (não Singleton com dependências scoped).
- [ ] Sem auto-validação via `FluentValidation.AspNetCore` em projeto novo; Minimal API usa `ValidationProblem`; validators async chamados com `ValidateAsync`.
- [ ] `ValidationException` vira 400/ProblemDetails; mensagens sem dados sensíveis.
- [ ] Cascade escolhido onde regras dependem umas das outras; `When` com `ApplyConditionTo` correto.
- [ ] Validators testados com `TestValidate`; upgrade 11→12 revisado (`CascadeMode`, `Transform`, `InjectValidator`, TFM ≥ net8).
- [ ] Unicidade/invariantes críticas garantidas também no banco, não só no validator.

## Fontes
- [MR] https://github.com/LuckyPennySoftware/MediatR (README, LICENSE.md, código) e wiki https://github.com/LuckyPennySoftware/MediatR/wiki — Home, Behaviors, License-Key-Configuration, Container-Feature-Support, Migration Guides 11→12 e 12.0→12.1; site de licença https://mediatr.io
- [FV] https://docs.fluentvalidation.net/en/latest/ (repo `FluentValidation/FluentValidation`, pasta `docs`): start, aspnet, di, async, cascade, conditions, collections, custom-validators, including-rules, rulesets, configuring, localization, testing, advanced, blazor, upgrading-to-12.
