---
name: aspnet-api-versioning
description: Projetar e revisar versionamento de Web APIs em ASP.NET Core - estratégias (sem versionamento, URI, query string, header, media type) e trade-offs oficiais da Microsoft, mudanças breaking vs não-breaking, e a implementação com a biblioteca de terceiros Asp.Versioning (AddApiVersioning, ApiVersion, readers, versão padrão, deprecação/sunset, version-neutral, OpenAPI versionado). Use quando o usuário pedir v1/v2 de endpoints, depreciar versões, escolher onde colocar a versão ou revisar compatibilidade de contrato. ⚠ O ASP.NET Core NÃO tem versionamento nativo documentado; a parte de implementação é biblioteca externa mantida pela .NET Foundation.
---

# Versionamento de API

**Proveniência (importante):**
- **Oficial Microsoft (Azure Architecture Center):** as *estratégias* de versionamento e seus trade-offs.
- **Biblioteca de terceiros (.NET Foundation, não faz parte do ASP.NET Core):** `Asp.Versioning.*` — implementação lida em `dotnet/aspnet-api-versioning` (docs do repositório). A doc do ASP.NET Core **não** documenta versionamento nativo. Marcado como **[LIB]** abaixo.
Ligações: `aspnet-http-endpoints`, `aspnet-minimal-api`, `aspnet-controllers`, `aspnet-openapi`, `dotnet-dto-review`, `aspnet-caching`.

## Quando versionar (oficial)
- A API evolui; o dev controla a API mas **não os clientes**. Sem versionamento pode servir a algumas APIs internas: **adicionar campos geralmente não quebra** clientes que ignoram campos desconhecidos; **remover/renomear campos ou mudar relacionamentos** são mudanças que quebram ⇒ considere versionar.
- Regra prática derivada: separar mudanças **aditivas** (sem versão nova) de **breaking** (versão nova ou novo recurso).

## Estratégias (oficial) e trade-offs
| Estratégia | Exemplo | Prós / contras segundo a doc |
|---|---|---|
| **URI** | `/v2/customers/3` | Simples, mas depende do servidor rotear; a doc diz que pode ficar **"unwieldy"** (difícil de manejar) conforme a API amadurece; "purismo": mesmo recurso não deveria ter URIs diferentes; complica **HATEOAS** (links com versão). "Cache-friendly" aparece só em resumo da página, não em texto confirmado. |
| **Query string** | `/customers/3?version=2` | Mesma URI por recurso; **o parâmetro deve ter default** (ex.: 1) se clientes antigos omitirem; o código precisa interpretar a query; complica HATEOAS; proxies/navegadores antigos podem **não cachear** URLs com query. Cache-friendly. |
| **Header** | `Custom-Header: api-version=2` | Cliente precisa enviar o header (usar default se ausente); lógica extra; links HATEOAS precisam do header; **pode duplicar dados no cache** do servidor/proxy. |
| **Media type** | `Accept: application/vnd.contoso.v1+json` | Bom para HATEOAS; servidor honra o `Accept` e confirma no `Content-Type`; sem tipo conhecido pode responder **406** ou tipo padrão; mesma ressalva de cache. |
- Escolha considerando **cache/proxy**, ferramentas de cliente, HATEOAS e custo de manter versões. A doc da biblioteca informa que o **padrão dela segue as Microsoft REST API Guidelines** (versão em query string/URL) e que header e media type **não** estão em conformidade com essas guidelines (embora o media type seja "aceito como REST").

## Implementação com Asp.Versioning [LIB]
- **Pacotes:** `Asp.Versioning.Http` (Minimal APIs), `Asp.Versioning.Mvc` (controllers), `Asp.Versioning.Mvc.ApiExplorer` + pacote de OpenAPI (a home da doc lista **`Asp.Versioning.OpenApi.ApiExplorer`**; confirme o nome exato no NuGet antes de citar `Asp.Versioning.OpenApi`) (documentação; ASP.NET Core 10+ com o OpenAPI da Microsoft/Scalar; versões anteriores usam Swashbuckle), `Asp.Versioning.Http.Client` (clientes), OData/gRPC existem. Verifique a versão atual no NuGet.
- **Minimal API:**
```csharp
builder.Services.AddProblemDetails();
builder.Services.AddApiVersioning();
var people = app.NewVersionedApi();
people.MapGet("/people", () => ...).HasApiVersion(1.0);   // "..." = corpo ilustrativo (não compila literalmente); API da biblioteca [LIB] não reverificada nesta passada
// por URL: var v1 = people.MapGroup("/people/v{version:apiVersion}").HasApiVersion(1.0);
```
- **Controllers:** `[ApiVersion(1.0)]` na classe (+ `[ApiController]`), `builder.Services.AddApiVersioning().AddMvc();`; rota por URL: `[Route("api/v{version:apiVersion}/[controller]")]`; uma action de versão específica: `[MapToApiVersion(3.0)]`. Versões também podem ser definidas por **conventions** (em vez de atributos).
- **`ApiVersioningOptions`:** `ApiVersionReader` (padrão = **query string `api-version` + segmento de URL**; `QueryStringApiVersionReader("v")`, `HeaderApiVersionReader("api-version")` — **não há header padrão/standard**, você define o nome —, `MediaTypeApiVersionReader` (parâmetro `v`; `Content-Type` tem preferência sobre `Accept`), `UrlSegmentApiVersionReader`; podem ser **combinados**); `DefaultApiVersion` (padrão **1.0**); **`AssumeDefaultVersionWhenUnspecified`** (**desligado por padrão**: sem versão a resposta é **400** ou **404**; **só habilite para legado** sem versionamento anterior, pois exigir versão de clientes existentes é breaking change); **`ReportApiVersions`** (envia `api-supported-versions` e `api-deprecated-versions`; desligado por padrão); `UnsupportedApiVersionStatusCode` (padrão **400**; com versão na URL é sempre 404, com media type é 406/415); `ApiVersionSelector`, `Policies`, `Conventions`.
- **Deprecação:** `[ApiVersion(1.0, Deprecated = true)]` — "deprecada" significa que **vai deixar de ser suportada** (a doc fala em **6 meses ou mais**); **version policies** emitem os headers de deprecação e `sunset` (a doc lida diz só que as policies aparecem nos headers da resposta; **os números RFC 9745/8594/8288 e a sintaxe `Policies.Deprecate(...).Effective(...)` não foram reconfirmados** — confira na doc da versão instalada); só ficam visíveis com `ReportApiVersions` ligado.
- **Version-neutral:** serviço que ignora a versão (ex.: health check) usa `[ApiVersionNeutral]`/`.IsApiVersionNeutral()`; **aceita qualquer versão e também nenhuma**. A home da doc diz que serviços compatíveis com as guidelines da Microsoft "devem suportar versionamento explícito"; neutral é exceção.
- **OpenAPI:** um documento por versão via API Explorer; `GroupNameFormat = "'v'VVV"` formata o nome do grupo (**não reconfirmado**: a página de opções do OpenAPI não foi lida); `VersionedOpenApiOptions` descreve cada documento (inclui avisos de deprecação/sunset).
- **Cache:** estratégias por header/media type interagem com cache (ver tabela e `aspnet-caching`; `Vary`).

## Boas práticas derivadas (CONVENÇÃO, marque como tal)
- Versionar **o contrato público** (DTOs/rotas), não o domínio; manter DTOs por versão (`dotnet-dto-review`); **não** duplicar lógica de negócio entre versões (compartilhe services).
- Definir política de suporte (tempo mínimo entre deprecar e remover), comunicar via headers e docs.
- Adicionar campo opcional = não breaking; remover/renomear/mudar tipo/semântica = breaking.
- Testar compatibilidade entre versões com testes de integração (`dotnet-integration-testing`).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Mudança breaking (remoção/renome/semântica) publicada sem nova versão | Alta |
| 2 | Versão obrigatória introduzida em API já existente sem `AssumeDefaultVersionWhenUnspecified` (quebra clientes) | Alta |
| 3 | `AssumeDefaultVersionWhenUnspecified` ligado em API nova (esconde ausência de versão) | Média |
| 4 | Versão só no header/media type sem avaliar cache/proxy e HATEOAS | Média |
| 5 | Versões antigas sem `Deprecated`/policies/`ReportApiVersions`; remoção sem aviso | Média |
| 6 | Lógica de negócio duplicada por versão em vez de services compartilhados | Média |
| 7 | Endpoint de health/infra sem `IsApiVersionNeutral`/`[ApiVersionNeutral]` quebrando monitoramento | Média |
| 8 | OpenAPI de uma única versão misturando versões | Baixa |
| 9 | Dependência da biblioteca sem checar compatibilidade com a versão do ASP.NET Core | Média |

## Fontes
- **Oficial:** Best practices for RESTful web API design (seção *Implement versioning*): https://learn.microsoft.com/en-us/azure/architecture/best-practices/api-design
- **Oficial:** Minimal APIs e controllers (onde o versionamento se pluga): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis · https://learn.microsoft.com/en-us/aspnet/core/web-api/
- **[LIB, terceiros]** Repositório Asp.Versioning (.NET Foundation): https://github.com/dotnet/aspnet-api-versioning
- **[LIB]** Documentação: https://dotnet.github.io/aspnet-api-versioning/
- **[LIB]** Microsoft REST API Guidelines (versionamento): https://github.com/microsoft/api-guidelines
