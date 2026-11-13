---
name: aspnet-controllers
description: Implementar e revisar controllers de Web API no ASP.NET Core ([ApiController], ControllerBase, [Route], [HttpGet]/[HttpPost]/..., ActionResult<T>, IActionResult, CreatedAtAction, [ProducesResponseType], binding source inference, validação automática 400). Use quando o usuário pedir para criar ou revisar um controller, escolher o tipo de retorno da action ou entender os comportamentos do [ApiController]. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# ASP.NET Core Web API com Controllers — implementar e revisar

Só afirmar o que a doc oficial diz (fontes no fim). Verbos/status/binding: `aspnet-http-endpoints`. Erros: `aspnet-error-handling`.

## Esqueleto (tutorial oficial)

```csharp
[Route("api/[controller]")]
[ApiController]
public class TodoItemsController : ControllerBase
{
    private readonly TodoContext _context;
    public TodoItemsController(TodoContext context) => _context = context;

    [HttpGet("{id}")]
    public async Task<ActionResult<TodoItemDTO>> GetTodoItem(long id)
    {
        var todoItem = await _context.TodoItems.FindAsync(id);
        if (todoItem == null) return NotFound();
        return ItemToDTO(todoItem);
    }

    [HttpPost]
    public async Task<ActionResult<TodoItemDTO>> PostTodoItem(TodoItemDTO todoDTO)
    {
        var todoItem = new TodoItem { IsComplete = todoDTO.IsComplete, Name = todoDTO.Name };
        _context.TodoItems.Add(todoItem);
        await _context.SaveChangesAsync();
        return CreatedAtAction(nameof(GetTodoItem), new { id = todoItem.Id }, ItemToDTO(todoItem));
    }

    [HttpPut("{id}")]
    public async Task<IActionResult> PutTodoItem(long id, TodoItemDTO todoDTO)
    {
        if (id != todoDTO.Id) return BadRequest();
        var todoItem = await _context.TodoItems.FindAsync(id);
        if (todoItem == null) return NotFound();
        todoItem.Name = todoDTO.Name;
        todoItem.IsComplete = todoDTO.IsComplete;
        try { await _context.SaveChangesAsync(); }
        catch (DbUpdateConcurrencyException) when (!TodoItemExists(id)) { return NotFound(); }
        return NoContent();
    }
}
```
Registro do contexto em `Program.cs` por DI (`AddDbContext`) e `builder.Services.AddControllers()` + `app.MapControllers()`.

## Regras da documentação

1. Controllers de API derivam de **`ControllerBase`**, não de `Controller` (este adiciona views; só use se o mesmo controller serve páginas e API).
2. `[Route("api/[controller]")]`: `[controller]` vira o nome da classe sem o sufixo `Controller`; rotas são case-insensitive; o nome do método **não** entra na URL.
3. **`[ApiController]`** habilita:
   - roteamento por atributos obrigatório;
   - **HTTP 400 automático** quando `ModelState` é inválido (não precisa de `if (!ModelState.IsValid)`), corpo `ValidationProblemDetails`;
   - **inferência de binding source**: serviço registrado → `[FromServices]`; complexo → `[FromBody]`; `IFormFile(Collection)` → `[FromForm]`; nome presente no template → `[FromRoute]`; demais → `[FromQuery]`;
   - inferência `multipart/form-data`;
   - **ProblemDetails** (RFC 7807) para respostas de erro (status ≥ 400), ex.: `NotFound()` gera corpo `ProblemDetails`.
   Pode ser aplicado por controller, em vários (classe base) ou no assembly.
4. **Tipos de retorno da action:**
   - *Tipo específico* (`Task<List<Product>>`): suficiente quando não há condições alternativas.
   - `IActionResult`: vários resultados possíveis, sem tipo de sucesso inferido (precisa `[ProducesResponseType(200, Type=...)]`).
   - **`ActionResult<T>`** (recomendado quando há 200 + erros): permite retornar `T` ou `ActionResult`; infere o tipo de sucesso, dispensa `Type =` no `[ProducesResponseType]`. Não funciona com interface como `T` (ex.: `IEnumerable<Product>` → converta, `ToList()`).
   - `HttpResults` (`Results<NotFound, Ok<Product>>`, `TypedResults`): compartilháveis com Minimal APIs, mas **não** usam formatters (sem content negotiation).
5. `IEnumerable<T>` é bufferizado; prefira `IAsyncEnumerable<T>` para iteração assíncrona (com `System.Text.Json` há streaming).
6. Métodos úteis de `ControllerBase`: `Ok`, `NotFound`, `BadRequest`, `NoContent`, `CreatedAtAction`, `Problem`, `ValidationProblem`.
7. Atributos: `[Route]`, `[HttpGet]`..., `[Consumes]`, `[Produces]`, `[ProducesResponseType]`, `[Bind]`.
8. Desligar comportamentos: `ConfigureApiBehaviorOptions` (`SuppressModelStateInvalidFilter`, inferência, ProblemDetails).

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | `[ApiController]` presente e derivando de `ControllerBase` |
| 2 | `[Route]` com atributo; sem `[action]` na rota de API |
| 3 | Retorno `ActionResult<T>`/`Task<ActionResult<T>>` com `[ProducesResponseType]` para status relevantes |
| 4 | `if (!ModelState.IsValid)` redundante com `[ApiController]` |
| 5 | `[HttpX]` no handler de erro (`/error`) → proibido (impede requisições) |
| 6 | DTOs de entrada/saída; nunca entidade (ver `dotnet-dto-review`) |
| 7 | Actions async com `await`; `CancellationToken` quando fizer sentido |
| 8 | Controller gordo: lógica de negócio dentro da action → mover para service (ver `dotnet-service-implementation`) |
| 9 | Injeção por construtor de interfaces, não `new` |
| 10 | Dois complexos no corpo, `[FromBody]` em tipo simples ausente |

## Fontes oficiais
- Criar web APIs: https://learn.microsoft.com/en-us/aspnet/core/web-api/
- Tipos de retorno de action: https://learn.microsoft.com/en-us/aspnet/core/web-api/action-return-types
- Tutorial: https://learn.microsoft.com/en-us/aspnet/core/tutorials/first-web-api
- Tratamento de erros em APIs: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/error-handling-api
