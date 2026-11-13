---
name: aspnet-http-endpoints
description: Implementar e revisar endpoints REST em ASP.NET Core com GET, POST, PUT, PATCH e DELETE - como passar dados (rota, query, header, body JSON), qual status code retornar (200, 201, 204, 400, 404), PUT vs PATCH, DTO de entrada/saída e overposting. Valido para Minimal APIs e Controllers. Use quando o usuário pedir para criar um CRUD, uma API, ou verificar se os verbos HTTP e retornos estão corretos. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# Endpoints HTTP no ASP.NET Core — verbos, dados e status codes

Só afirmar o que a doc oficial diz (fontes no fim); caso contrário, buscar antes. Estilo específico: `aspnet-minimal-api` ou `aspnet-controllers`. DTOs: `dotnet-dto-review`. Erros: `aspnet-error-handling`.

## Tabela CRUD (padrão dos tutoriais oficiais)

| Verbo | Rota | Corpo de entrada | Sucesso | Falha |
|---|---|---|---|---|
| `GET` | `/todoitems` | nenhum | `200 OK` + lista de DTOs | — |
| `GET` | `/todoitems/{id}` | nenhum | `200 OK` + DTO | `404 NotFound` |
| `POST` | `/todoitems` | DTO | `201 Created` + header `Location` + DTO criado | `400` (validação) |
| `PUT` | `/todoitems/{id}` | DTO **completo** | `204 NoContent` | `404`; `400` se `id` da rota ≠ `id` do corpo (versão controller) |
| `PATCH` | `/todoitems/{id}` | DTO parcial (propriedades nullable) | `204 NoContent` | `404` |
| `DELETE` | `/todoitems/{id}` | nenhum | `204 NoContent` | `404` |

- **PUT** exige a entidade inteira (segundo a especificação HTTP, como diz a doc). Para atualização parcial use **PATCH**. Com DTO de patch, propriedades `bool?`/`string?` permitem distinguir "não enviado" de "enviado como false". (A doc também aponta JSON Patch para cenários avançados.)
- **POST** devolve a URL do novo recurso: Minimal API `TypedResults.Created($"/todoitems/{item.Id}", dto)`; Controller `CreatedAtAction(nameof(GetTodoItem), new { id = item.Id }, dto)`.

## De onde vêm os dados (binding)

| Fonte | Minimal API | Controller com `[ApiController]` |
|---|---|---|
| Rota (`/{id}`) | parâmetro com mesmo nome do template | inferido `[FromRoute]` |
| Query string (`?page=2`) | tipos simples fora da rota | inferido `[FromQuery]` para o restante |
| Header | `[FromHeader(Name="X-...")]` | `[FromHeader]` |
| Corpo JSON | tipo complexo em POST/PUT/PATCH (último recurso da precedência) | tipo complexo inferido `[FromBody]` |
| Serviço (DI) | tipo registrado no container, sem atributo | tipo registrado inferido `[FromServices]` |

Regras da doc:
- Minimal API: `GET`, `HEAD`, `OPTIONS`, `DELETE` **não** fazem bind do corpo implicitamente. Para ler corpo nesses verbos use `[FromBody]` explicitamente.
- Parâmetro opcional: tipo nullable ou valor default (`int? pageNumber`). Se o valor é inválido e o parâmetro é nullable, o handler **não** executa.
- Falha de bind: `TryParse` falso → 400; JSON inválido → 400; content-type diferente de `application/json` → 415.
- Controller: mais de um parâmetro vindo do corpo → exceção. `[FromBody]` não é inferido para tipos simples (`string`, `int`): usar o atributo.
- `[FromRoute]` não é bom quando o valor pode conter `%2f`: use `[FromQuery]`.
- Tipos especiais ligados automaticamente: `HttpContext`, `HttpRequest`, `HttpResponse`, `CancellationToken` (= `RequestAborted`), `ClaimsPrincipal`, `Stream`, `PipeReader`.
- Em Minimal API, restrições de rota (`{id:int}`) e catch-all (`{*rest}`) são suportadas; valor não conversível lança `BadHttpRequestException`.

## DTO e overposting
Em produção, exponha um **subconjunto do modelo** (DTO) para entrada e saída: evita overposting (cliente setar campos que não deve, ex.: `Secret`), esconde propriedades, reduz payload e achata grafos. No update, carregue a entidade e copie **somente** os campos permitidos do DTO; nunca faça bind direto da entidade.

## Async e cancelamento
Handlers/actions usam `async Task` + `await` (`FindAsync`, `ToListAsync`, `SaveChangesAsync`). Aceite `CancellationToken` como parâmetro: o ASP.NET o liga a `RequestAborted`. Ver `csharp-async-await`.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Verbo coerente com a operação (GET sem efeito colateral; criação = POST; troca total = PUT; parcial = PATCH) |
| 2 | POST retorna 201 com Location (não 200) |
| 3 | PUT/PATCH/DELETE bem-sucedidos retornam 204 (padrão da doc) e 404 quando não existe |
| 4 | Entidade de banco usada como parâmetro/retorno em vez de DTO (overposting/vazamento) |
| 5 | `id` da rota usado como fonte da verdade; se há `id` no corpo, comparar (400 em divergência) |
| 6 | Corpo esperado em GET/DELETE sem `[FromBody]` (Minimal API) |
| 7 | Mais de um complexo no corpo (controller) |
| 8 | Validação de entrada presente (ver skill de validação) |
| 9 | Métodos síncronos de EF (`ToList`, `SaveChanges`) em endpoint |
| 10 | Sem `CancellationToken` em operações de I/O longas |
| 11 | PUT parcial usado como se fosse PATCH, ou PATCH com tipo não-nullable perdendo "não enviado" |

## Fontes oficiais
- Tutorial Minimal API: https://learn.microsoft.com/en-us/aspnet/core/tutorials/min-web-api
- Tutorial Web API com controllers: https://learn.microsoft.com/en-us/aspnet/core/tutorials/first-web-api
- Parameter binding (Minimal APIs): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/parameter-binding
- Criar web APIs (ApiController, binding source inference): https://learn.microsoft.com/en-us/aspnet/core/web-api/
- Respostas (Minimal APIs): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/responses
