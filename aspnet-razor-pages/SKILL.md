---
name: aspnet-razor-pages
description: Implementar e revisar apps ASP.NET Core Razor Pages (UI server-rendered orientada a página) - @page, PageModel, handlers (OnGet/OnPost/named handlers), [BindProperty], validação, geração de URL (RedirectToPage, asp-page), rotas customizadas, layouts/partials/_ViewImports, TempData/ViewData, antiforgery, page filters, autorização por convenção (AuthorizePage/AuthorizeFolder), testes unitários de PageModel. Use quando o usuário pedir páginas Razor, formulários server-side, CRUD com Razor Pages ou revisar PageModels. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# Razor Pages

Só afirmar o que a doc oficial diz (fontes no fim). Para APIs use `aspnet-minimal-api`/`aspnet-controllers`; para UI interativa de componentes, `aspnet-blazor`. Validação: `aspnet-validation`. Binding/filtros (compartilhados com MVC): `aspnet-mvc-controllers-filters`. CSRF: `aspnet-web-security`. Testes: `dotnet-unit-testing`.

## Conceito e setup
Razor Pages simplifica cenários **orientados a página** (mais produtivo que controllers+views). Habilite com `builder.Services.AddRazorPages()` e `app.MapRazorPages()`. A diretiva **`@page`** (deve ser a **primeira** diretiva Razor) transforma o arquivo numa action MVC que trata requisições **sem controller**. O runtime procura em **`Pages/`**; a URL vem do **caminho do arquivo** (`/Pages/Store/Contact.cshtml` → `/Store/Contact`; `Index` é a página padrão). Convenção: `Pages/X.cshtml` + `Pages/X.cshtml.cs` com classe **`XModel : PageModel`**. O `PageModel` separa lógica de apresentação, permite **DI** e **teste unitário**. Template: `dotnet new webapp`.

## Handlers
- Métodos `On<Verbo>[Async]`: `OnGet` (inicializa estado), `OnPost` (envio de formulário), etc.; o sufixo `Async` é opcional. Retorno padrão é `PageResult` (`Page()`); `void` renderiza a página. **`RedirectToPage(...)`** (como `RedirectToAction`) é o padrão após sucesso no POST (padrão de redirecionar após POST).
- Fluxo típico de `OnPostAsync`: **checar `ModelState.IsValid`** → se inválido, `return Page()` (reexibe com mensagens); se válido, salva e redireciona.
- **Named handlers:** `OnPost<Nome>Async` selecionado por `?handler=Nome` (`asp-page-handler="Nome"`); o nome é o texto entre `On<Verbo>` e `Async`. Uma página pode ter vários. Rota pode colocar o handler no caminho: `@page "{handler?}"`.
- **HEAD:** sem `OnHead`, cai no `OnGet`.
- **Qualquer** handler de verbo HTTP pode ser criado; o roteamento por página/ID usa `@page "{id:int}"` (constraint; sem valor conversível → 404; `{id:int?}` para opcional).

## Binding e validação
- **`[BindProperty]`** na propriedade do PageModel (opt-in) evita converter HTTP→modelo manualmente; **por padrão só faz bind em verbos não-GET** (`SupportsGet = true` para GET). **Não use `[BindProperty]` em modelos com propriedades que o cliente não deve alterar** (overposting; use view model/DTO — ver `dotnet-dto-review`). Binding, validação e action results funcionam **como em controllers**.
- **Validação:** regras declarativas (DataAnnotations) no modelo, **impostas em todo lugar**; tag helpers (`asp-validation-for`, `asp-validation-summary`) + jQuery validation geram validação **cliente**, **mas o servidor sempre revalida** (cliente é conveniência; pode ser contornada). `[Required]`/`MinimumLength` aceitam espaço em branco; tipos valor são implicitamente obrigatórios; `[DataType]` só formata.
- **Antiforgery:** Razor Pages já são protegidas (o **FormTagHelper** injeta o token nos `<form>`); não desative.

## Estado entre requisições
- **`[ViewData]`** (propriedade guardada no `ViewDataDictionary`, ex.: título lido pelo layout) e **`[TempData]`** (guardado **até ser lido**; útil em redirects; `Keep`/`Peek` para não apagar). Para outros mecanismos de estado ver `fundamentals/app-state`.

## URLs, layout e organização
- **Geração de URL:** use `RedirectToPage`, `Url.Page`, `<a asp-page="...">` em vez de URLs fixas (usa roteamento, codifica parâmetros). Nome **absoluto** `/Index` (a partir de `Pages/`), **relativo** `./Index`, `../Index`, `Index` (combinado com a página atual; **renomear pasta não quebra links relativos**). Área: `RedirectToPage("/Index", new { area = "Services" })`.
- **Rotas:** `@page "/Some/Other/Path"` (substitui), `@page "item"` (acrescenta segmento), `@page "{id}"` (parâmetro), `~/` raiz-relativo. Palavras reservadas não servem como segmento/parâmetro (ver *Reserved routing names*).
- **Layout/partials/templates/Tag Helpers** funcionam como em views; `_ViewStart.cshtml`, `_ViewImports.cshtml` (`@namespace`, `@addTagHelper`). **Coloque o layout em `Pages/Shared`** (não em `Views/Shared`: Razor Pages usa hierarquia de pastas). A busca de views/partials começa na **pasta da página** e sobe.
- Raiz diferente de `/Pages`: `WithRazorPagesAtContentRoot()` (content root) ou `WithRazorPagesRoot("/caminho")`; `AddRazorPages(o => ...)` expõe `RazorPagesOptions` (raiz e convenções). Compartilhar páginas em bibliotecas: **Razor class library** (`ui-class`).

## Filters
**Page filters** (`IPageFilter`/`IAsyncPageFilter`) rodam **depois da seleção do handler, antes do model binding** (`OnPageHandlerSelected`), **antes do handler após o binding** (`OnPageHandlerExecuting`) e **depois** (`OnPageHandlerExecuted`); aplicáveis **por página ou globalmente**, **não por handler**; aceitam DI (`ServiceFilter`/`TypeFilter`). **Implemente sync OU async, não ambos** (se ambos, só async). Só filtros dão acesso ao **contexto da página** (middleware não). Filtros de MVC "Action" **não** se aplicam a Razor Pages.

## Autorização
- **Convenções no startup** (`AddRazorPages(o => o.Conventions...)`): `AuthorizePage("/Contact")`, `AuthorizePage("/Contact", "PolicyName")`, `AuthorizeFolder("/Private")`, `AllowAnonymousToPage/Folder`, `AuthorizeAreaPage/Folder`. O caminho é o **View Engine path** (relativo à raiz de Razor Pages, sem extensão, só `/`). Também vale **`[Authorize]` na classe do PageModel**. Detalhes de políticas/roles/recursos: `aspnet-authentication-authorization`.

## Testes
Teste a lógica do `PageModel` em unidade: mocke dependências (ex.: repositório/serviço), invoque o handler e verifique propriedades do modelo e o `IActionResult` retornado (ver `dotnet-unit-testing`; doc *Razor Pages unit tests*). Para o pipeline completo use `dotnet-integration-testing`.

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | `OnPost` sem checar `ModelState.IsValid`; confiar só em validação cliente | Alta |
| 2 | `[BindProperty]` em entidade de domínio (overposting) | Alta |
| 3 | `@page` não é a primeira diretiva; pasta/arquivo fora do padrão `Pages/` | Baixa |
| 4 | POST que retorna `Page()` após sucesso (reenvio ao F5) em vez de `RedirectToPage` | Média |
| 5 | URLs fixas em vez de `asp-page`/`RedirectToPage` | Baixa |
| 6 | Layout em `Views/Shared` num app só de Razor Pages | Baixa |
| 7 | Página sensível sem `AuthorizePage/Folder`/`[Authorize]`; caminho de convenção com extensão/`\` | Alta |
| 8 | Antiforgery desabilitado ou formulário escrito à mão sem token | Alta |
| 9 | Page filter implementando sync e async; lógica de negócio dentro do filtro | Média |
| 10 | Lógica de negócio/EF direto no PageModel em vez de service | Média |
| 11 | `TempData` com objetos grandes/sensíveis | Média |

## Fontes oficiais
- Razor Pages architecture: https://learn.microsoft.com/en-us/aspnet/core/razor-pages/
- Filtros de Razor Pages: https://learn.microsoft.com/en-us/aspnet/core/razor-pages/filter
- Convenções de rota/app: https://learn.microsoft.com/en-us/aspnet/core/razor-pages/razor-pages-conventions
- Convenções de autorização: https://learn.microsoft.com/en-us/aspnet/core/razor-pages/security/authorization/conventions
- Unit tests de Razor Pages: https://learn.microsoft.com/en-us/aspnet/core/test/razor-pages-tests
- Razor class library UI: https://learn.microsoft.com/en-us/aspnet/core/razor-pages/ui-class
- Tutorial: https://learn.microsoft.com/en-us/aspnet/core/tutorials/razor-pages/
