---
name: aspnet-blazor
description: Fundamentos e revisão de Blazor (Blazor Web App) - componentes Razor, render modes (Static Server, Interactive Server, WebAssembly, Auto), prerendering, ciclo de vida (SetParametersAsync, OnInitialized, OnParametersSet, OnAfterRender), disposal e unsubscribe de eventos, uso do EF Core em Blazor Server (DbContext factory), autorização em componentes. Use quando o usuário pedir componentes Blazor, escolher render mode, ou revisar vazamentos/estado em Blazor. Based on official Microsoft Learn docs (ASP.NET Core 10). Cobre os fundamentos; consulte a doc para formulários, JS interop e segurança em profundidade.
---

# Blazor — fundamentos e revisão

Só afirmar o que a doc oficial diz (fontes no fim). Blazor é muito amplo: esta skill cobre **conceitos centrais** (render modes, ciclo de vida, disposal, EF Core, autorização); para formulários, validação, JS interop, state management, hybrid/PWA, consulte as páginas indicadas. Autorização: `aspnet-authentication-authorization`. Validação: `aspnet-validation`.

## Componentes e modelo
- **Razor components** (`.razor` ou classes derivadas de `ComponentBase`; também `IComponent` para controle baixo-nível, ao custo de disparar renderização manualmente): partes autocontidas de UI com lógica; **aninháveis, reutilizáveis, compartilháveis** entre projetos e usáveis em MVC/Razor Pages. Não confunda com views/Razor Pages.
- Convenção da doc para diretivas no topo: `@page`, `@rendermode`, `@using`, demais diretivas em ordem alfabética (apenas convenção). Nas amostras da doc usa-se `this.` e não prefixo `_` em campos (difere das engineering guidelines do ASP.NET; use o padrão da sua equipe).
- **Interatividade** permite responder a eventos DOM e mudanças de estado ligadas a membros C#; **a maioria dos exemplos da doc exige interatividade** (global ou por componente).

## Render modes (Blazor Web App)
Cada componente adota um **render mode** (diretiva/atributo `@rendermode`, na definição ou na instância):
| Modo | Onde renderiza | Interativo |
|---|---|---|
| **Static Server** (static SSR) | servidor | ❌ |
| **Interactive Server** (Blazor Server) | servidor (conexão/circuit) | ✔ |
| **Interactive WebAssembly** (CSR) | cliente (projeto cliente separado) | ✔ |
| **Interactive Auto** | servidor primeiro, depois CSR após baixar o bundle | ✔ |
- **Prerendering** (HTML inicial no servidor sem handlers) é **habilitado por padrão** em componentes interativos; melhora a percepção de velocidade e o **SEO**; pode ser desabilitado por componente. **Blazor WebAssembly standalone não tem render mode.**
- Um Blazor Web App precisa ser configurado (`AddRazorComponents().AddInteractive...`, `MapRazorComponents<App>()`); componentes WebAssembly ficam num **projeto cliente**.

## Ciclo de vida (resumo)
`SetParametersAsync` (aplica `[Parameter]`/`[CascadingParameter]`; ao sobrescrever, **chame `await base.SetParametersAsync(parameters)`**; `ParameterView.TryGetValue` é **case-sensitive**, diferente do roteamento) → `OnInitialized{Async}` (**inicialização única** por instância) → `OnParametersSet{Async}` → render → `OnAfterRender{Async}`. **O pai renderiza antes dos filhos**; com inicialização **assíncrona** a ordem de conclusão pai/filho não é determinística. Cuidado com **prerendering** (o componente inicializa duas vezes: prerender e interativo; a doc trata *quiescence* e persistência de estado pré-renderizado).

## Disposal (evitar vazamentos)
- Componente com `IDisposable`/`IAsyncDisposable` é descartado quando **removido da UI**; **não dependa do momento exato**; se implementar ambos, **só o async executa**; `IAsyncDisposable` não deve demorar.
- **Sempre cancele assinatura de eventos .NET** no `Dispose` (e evite lambdas anônimas em eventos que precisam ser removidos). Descarte `IJSObjectReference`/`DotNetObjectReference` (vaza memória JS/.NET). Timers: descarte no `Dispose`. Atribuir `null` a objetos descartados raramente faz sentido.

## EF Core em Blazor (Server)
- Blazor Server é **stateful**: o estado do usuário vive em memória num **circuit** (serviços scoped duram o circuit). O **`DbContext` scoped (padrão) compartilha instância entre componentes do mesmo usuário**: problemas de **concorrência** (DbContext não é thread-safe). **Recomendação:** `AddDbContextFactory` e **crie um `DbContext` novo por operação** (escopo de método) ou por **vida do componente** (se necessário), descartando-o (ver `efcore-dbcontext-connection`). Carregue com indicador na UI para o usuário não acionar ações durante o carregamento. `EnableSensitiveDataLogging` só em dev.

## Autorização
`[Authorize]` só em componentes `@page` roteados; para partes de uma página use `AuthorizeView`; `fallback policy` do servidor não vale em WebAssembly standalone (ver `aspnet-authentication-authorization`). Segurança em Blazor (SSR estático, interativo, WebAssembly, OIDC/Entra) tem páginas próprias.

## Outros pontos úteis
`@page` rotas; `[Parameter]`/cascading; `EventCallback`; bindings `@bind`; layouts; CSS isolation; `DynamicComponent`; chamar Web API (`call-web-api`); JS interop; testes (bUnit, fora da doc); desempenho (`blazor/performance`).

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | `DbContext` scoped injetado direto em componente Interactive Server (usar factory) |
| 2 | Eventos/timers assinados sem `Dispose`; referências JS sem descarte |
| 3 | Lógica de inicialização que assume execução única apesar do prerendering (duas execuções) |
| 4 | Render mode inadequado (ex.: Server onde o app precisa ser offline/escala; WebAssembly com segredos no cliente) |
| 5 | `[Authorize]` em componente filho (não é avaliado fora de `@page`) |
| 6 | Sobrescrita de `SetParametersAsync` sem chamar o base |
| 7 | `OnInitializedAsync` longo sem estado de carregamento |
| 8 | Segredos/chaves em código WebAssembly (baixado pelo cliente) |

## Fontes oficiais
- Blazor (índice): https://learn.microsoft.com/en-us/aspnet/core/blazor/
- Fundamentals: https://learn.microsoft.com/en-us/aspnet/core/blazor/fundamentals/
- Razor components: https://learn.microsoft.com/en-us/aspnet/core/blazor/components/
- Render modes: https://learn.microsoft.com/en-us/aspnet/core/blazor/components/render-modes
- Component lifecycle: https://learn.microsoft.com/en-us/aspnet/core/blazor/components/lifecycle
- Component disposal: https://learn.microsoft.com/en-us/aspnet/core/blazor/components/component-disposal
- Blazor com EF Core: https://learn.microsoft.com/en-us/aspnet/core/blazor/blazor-ef-core
- State management: https://learn.microsoft.com/en-us/aspnet/core/blazor/state-management/
- Forms e validação: https://learn.microsoft.com/en-us/aspnet/core/blazor/forms/
- Segurança: https://learn.microsoft.com/en-us/aspnet/core/blazor/security/
