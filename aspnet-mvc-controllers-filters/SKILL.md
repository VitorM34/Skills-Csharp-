---
name: aspnet-mvc-controllers-filters
description: Implementar e revisar recursos de MVC/controllers no ASP.NET Core além do básico - filtros (authorization, resource, action, exception, result), ordem e escopo, filtros com DI (ServiceFilter/TypeFilter), model binding (fontes, [BindProperty], SupportsGet, tipos simples vs complexos), roteamento por atributos vs convencional, token replacement, DI em controllers e options. Use quando o usuário pedir filtros customizados, binding de parâmetros/formulários, rotas de controllers ou revisar controllers complexos. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# MVC / controllers — filtros, model binding, roteamento e DI

Só afirmar o que a doc oficial diz (fontes no fim). Básico de Web API com controllers: `aspnet-controllers`. Endpoints Minimal API: `aspnet-minimal-api`. Middleware: `aspnet-middleware-pipeline`.

## Filtros (MVC, Razor Pages e controllers de API)
Tratam **preocupações transversais** (erros, cache, configuração, autorização, log) sem duplicar código. **Não funcionam diretamente com componentes Razor.**
| Tipo | Quando roda / o que faz |
|---|---|
| **Authorization** | **primeiro**; decide se o usuário está autorizado; **curto-circuita** se não |
| **Resource** | depois da autorização; `OnResourceExecuting` roda **antes** do resto do pipeline (ex.: antes do model binding) e `OnResourceExecuted` depois de tudo |
| **Action** | imediatamente antes/depois do método da action; podem **alterar argumentos** e **resultado**; **não suportados em Razor Pages** |
| **Endpoint filters** | como action filters mas para Minimal APIs **e** actions (ver `aspnet-minimal-api`) |
| **Exception** | aplicam política global a exceções **não tratadas** ocorridas **antes do corpo da resposta ser escrito**; rodam após model binding e action filters, antes do resultado; **não** pegam exceções de middleware, roteamento ou model binding |
| **Result** | imediatamente antes/depois do `ActionResult`; **só rodam se a action executou com sucesso**; úteis para lógica que envolve view/formatter |
Razor Pages também têm *Razor Page filters*; filtros **não** se aplicam a handlers de Razor Pages (só ao page model ou globalmente).
- **Implemente a versão síncrona OU a assíncrona, nunca as duas** (se ambas, só a async é chamada). Escopo/ordem: **global envolve de classe, que envolve de método**; o código "depois" roda na ordem inversa do "antes". Filtros de nível de controller têm `Order = int.MinValue` e **não** podem rodar depois dos de método (use `Order`/`IOrderedFilter` explicitamente).
- **DI em filtros:** filtro adicionado por **tipo** é **type-activated**: uma instância **por requisição** com dependências do DI; por **instância** (a mesma em todas as requisições). **Filtros como atributos direto na classe/action não recebem dependências por DI**: use **`[ServiceFilter]`** (resolve do DI; registre o tipo em `Program.cs`), **`[TypeFilter]`** ou implemente **`IFilterFactory`** no atributo.
- Evite filtros só para logging (o framework já loga actions e eventos); logs de filtro devem tratar **comportamento de domínio específico do filtro**.

## Model binding
- Converte dados da requisição em parâmetros/propriedades. **Fontes padrão (em ordem):** campos de formulário, corpo da requisição (**apenas em controllers com `[ApiController]`**), route data, query string, arquivos enviados; a busca para cada alvo segue essa ordem, com exceções: **route data e query só para tipos simples**; arquivos só para `IFormFile`/`IEnumerable<IFormFile>`.
- Atributos para fixar a fonte: `[FromQuery]`, `[FromRoute]`, `[FromForm]`, `[FromBody]`, `[FromHeader]` (aplicados **por propriedade**, não na classe; aceitam nome). **`[FromBody]` em no máximo um parâmetro por action** (o stream é lido uma vez pelo input formatter). Fontes extras via **value providers** customizados (`Insert(0, ...)` para ser o primeiro).
- **Tipo simples** = convertido de uma string via `TypeConverter` ou `TryParse` (a doc recomenda criar um deles para tipos próprios); **complexo** = vários valores.
- **`[BindProperty]`/`[BindProperties]`** (Razor Pages/controllers): por padrão **propriedades não são bindadas em GET**; `SupportsGet = true` para habilitar. **Overposting**: use view model/DTO ou `[Bind]` (ver `dotnet-dto-review`).
- **Sem valor para uma propriedade:** por padrão **não há erro de ModelState**; tipos valor não-nullable recebem `default(T)` (ex.: `int id` → 0), complexos são criados pelo construtor padrão. Com nullable reference types habilitado, não-nullable é tratado como `[Required]` (ver `aspnet-validation`).

## Roteamento de controllers
- **Convencional** (`MapControllerRoute`, padrão `{controller=Home}/{action=Index}/{id?}`): para **controllers com views**; baseado só nos nomes de controller/action. **APIs REST devem usar roteamento por atributos** (`[Route]`, `[HttpGet]`...) que modela recursos com **verbos HTTP**; nome de controller/action **não participa** do casamento, salvo **token replacement** (`[controller]`, `[action]`). Templates na action que começam com `/` ou `~/` **não se combinam** com o template do controller.
- Aplicações normalmente **não precisam chamar `UseRouting`/`UseEndpoints`** (o `WebApplicationBuilder` já envolve). Ver `aspnet-middleware-pipeline` (precedência, `Order`).
- `[ApiController]` **exige** roteamento por atributos (ver `aspnet-controllers`).

## DI em controllers
- Injeção por **construtor** (preferida; serviços via interface), `[FromServices]`/`[FromKeyedServices]` na action. **Não injete `IConfiguration` direto** no controller: use o **options pattern** (`aspnet-configuration-options`). **Controllers não são registrados no container por padrão**: o `DefaultControllerActivator` os cria, resolvendo só as dependências do construtor (use `AddControllersAsServices` se precisar).

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Filtro como atributo com dependência de construtor (usar `ServiceFilter`/`TypeFilter`) |
| 2 | Filtro implementando sync **e** async |
| 3 | Exception filter esperando capturar erros de binding/middleware/roteamento |
| 4 | Lógica de negócio dentro de filtros (deveria estar em services) |
| 5 | Mais de um `[FromBody]`; `[FromBody]` em tipo simples sem atributo |
| 6 | Propriedades bindadas por GET sem `SupportsGet`; overposting por bind de entidade |
| 7 | API REST com roteamento convencional; rotas duplicadas/ambíguas |
| 8 | `IConfiguration` injetada no controller |
| 9 | Filtros de log duplicando o logging do framework |

## Fontes oficiais
- Filters: https://learn.microsoft.com/en-us/aspnet/core/mvc/controllers/filters
- Model binding: https://learn.microsoft.com/en-us/aspnet/core/mvc/models/model-binding
- Routing to controller actions: https://learn.microsoft.com/en-us/aspnet/core/mvc/controllers/routing
- DI into controllers: https://learn.microsoft.com/en-us/aspnet/core/mvc/controllers/dependency-injection
- Unit test controller logic: https://learn.microsoft.com/en-us/aspnet/core/mvc/controllers/testing
