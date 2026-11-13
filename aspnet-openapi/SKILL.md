---
name: aspnet-openapi
description: Gerar e revisar documentação OpenAPI no ASP.NET Core - AddOpenApi, MapOpenApi, metadata de endpoints (WithSummary, WithName, Produces, TypedResults), transformers, múltiplos documentos, geração em build, Swagger UI/Scalar só em desenvolvimento. Use quando o usuário pedir swagger/OpenAPI, documentar endpoints ou revisar metadata de resposta. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# OpenAPI no ASP.NET Core

Só afirmar o que a doc oficial diz (fontes no fim). Endpoints: `aspnet-minimal-api`, `aspnet-controllers`, `aspnet-http-endpoints`.

## Gerar o documento
Pacote `Microsoft.AspNetCore.OpenApi` (suporte nativo a **geração**; **não** inclui UI).
```csharp
builder.Services.AddOpenApi();            // documento "v1" por padrão
var app = builder.Build();
if (app.Environment.IsDevelopment()) app.MapOpenApi();   // /openapi/v1.json
```
- Versão do OpenAPI padrão: **3.1 no .NET 10** (3.2 só a partir do .NET 11); altere com `OpenApiOptions.OpenApiVersion`.
- JSON por padrão; **YAML** mapeando o endpoint com sufixo `.yaml`/`.yml`.
- Nome do documento (padrão `v1`), rota (`/openapi/{documentName}.json`; **não** remova `documentName` da rota), **múltiplos documentos** (`AddOpenApi("v2")`; `OpenApiOptions.ShouldInclude` decide os endpoints; `WithGroupName`/`[EndpointGroupName]`).
- **O endpoint não tem autorização por padrão**: restrinja (`MapOpenApi().RequireAuthorization(...)`). O documento é **regenerado a cada requisição** (permite transformers dinâmicos); cacheie quando aplicável.
- **Geração em build:** pacote `Microsoft.Extensions.ApiDescription.Server` salva o documento (por padrão em `obj`) no `dotnet build`.
- **UIs (Swagger UI, ReDoc, Scalar) não vêm por padrão** e, como boa prática de **limitar divulgação de informação, devem ficar habilitadas só em Development**. Linter: Spectral.

## Metadata (controllers com `[ApiController]` e Minimal APIs)
| Metadata | Atributo | Extension method (Minimal API) | Outros |
|---|---|---|---|
| summary | `[EndpointSummary]` | `WithSummary` | |
| description | `[EndpointDescription]` | `WithDescription` | |
| tags | `[Tags]` | `WithTags` | |
| operationId | `[EndpointName]` | `WithName` (único, case-sensitive) | |
| parâmetros | `[FromQuery]`, `[FromRoute]`, `[FromHeader]`, `[FromForm]` | | |
| requestBody | `[FromBody]` | `Accepts` | |
| responses | `[Produces]`, `[ProducesResponseType]` | `Produces<T>`, `ProducesProblem` | **`TypedResults`** (metadata automática) |
| excluir | `[ExcludeFromDescription]`, `[ApiExplorerSettings(IgnoreApi = true)]` | `ExcludeFromDescription()` | |
- Também coleta de **XML doc comments** (ver "XML documentation comments").
- Boa prática: `TypedResults`/`Results<...>` dispensa anotar `Produces` manualmente.

## Transformers (personalização)
- **Document**, **operation** e **schema transformers**. Ordem: schema (ao registrar o schema), operation (ao adicionar a operação), na ordem de adição. Operation transformer **por endpoint** com `AddOpenApiOperationTransformer` (ex.: security scheme, descrição de resposta). Requisitos de segurança condicionais por metadata: use operation transformer; o *security scheme* precisa estar registrado no documento (ex.: `BearerSecuritySchemeTransformer`).
- Schemas de **enum** são sempre `$ref` em `components.schemas` (personalizável via `CreateSchemaReferenceId`). Ex.: schema transformer para `decimal` com `format: decimal`.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | `AddOpenApi` + `MapOpenApi` presentes; UI só em Development |
| 2 | Documento exposto em produção sem autorização (vaza a superfície da API) |
| 3 | Todos os endpoints com respostas documentadas (TypedResults/Produces/ProducesProblem) |
| 4 | `WithName` único; tags/summary preenchidos |
| 5 | Segurança (Bearer/OAuth) descrita via transformers |
| 6 | Versionamento: documentos separados por versão/grupo |
| 7 | Endpoints internos/health excluídos da descrição |
| 8 | Geração em build configurada se o documento é artefato de CI |

## Fontes oficiais
- OpenAPI overview: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/overview
- Generate OpenAPI documents: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/aspnetcore-openapi
- Include OpenAPI metadata: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/include-metadata
- Customize OpenAPI documents (transformers): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/customize-openapi
- Use OpenAPI documents (Swagger UI/Scalar/Spectral): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/using-openapi-documents
