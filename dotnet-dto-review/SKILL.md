---
name: dotnet-dto-review
description: Implementar e revisar Data Transfer Objects (DTOs) em C#/ASP.NET Core - request/response DTOs, records posicionais, propriedades init/required, overposting, mapeamento entidade-DTO, DTO de PATCH com nullable, projeção LINQ para DTO, atributos de validação e JSON. Use quando o usuário pedir para criar DTOs, verificar se os DTOs estão corretos ou se está vazando entidade na API. Based on official Microsoft Learn docs.
---

# DTOs em C#/ASP.NET Core — implementar e revisar

Só afirmar o que a doc oficial diz (fontes no fim). Observação honesta: a Microsoft **não tem uma página única "DTO"** nesta versão da doc; as regras abaixo vêm dos tutoriais oficiais de Web API (que usam DTOs) e das páginas de `record`, `required`, validação e EF Core.

## Por que DTO (lista oficial dos tutoriais)
1. Evitar **overposting** (cliente definindo campos que não deve, ex.: `Secret`).
2. Ocultar propriedades que o cliente não deve ver.
3. Omitir propriedades para reduzir o tamanho do payload.
4. Achatar grafos de objetos com aninhamento.
Doc: "em aplicações de produção, use um subconjunto do modelo para restringir os dados que o cliente envia e recebe; segurança é um motivo importante".

## Como implementar

### 1. Entidade (interna) vs DTO (contrato público)
```csharp
public class Todo            // entidade
{
    public int Id { get; set; }
    public string? Name { get; set; }
    public bool IsComplete { get; set; }
    public string? Secret { get; set; }     // nunca sai pela API
}

public class TodoItemDTO     // DTO do tutorial oficial
{
    public int Id { get; set; }
    public string? Name { get; set; }
    public bool IsComplete { get; set; }
    public TodoItemDTO() { }
    public TodoItemDTO(Todo t) => (Id, Name, IsComplete) = (t.Id, t.Name, t.IsComplete);
}
```

### 2. Forma do DTO com C# moderno
- **Record posicional** (reference type; propriedades `init` imutáveis; igualdade por valor; `with`): ideal para DTO de saída e requests simples.
  ```csharp
  public record CreateProductRequest([Required] string Name, [Range(1, 1000)] int Quantity);
  ```
- **Classe/record com `required` + `init`** quando precisa de object initializer: `public required string Name { get; init; }`.
  - `required` obriga o inicializador a definir o membro; pode ser `null` com aviso se tipo é não-nullable; **não** vale em parâmetro posicional (declare a propriedade explicitamente).
- **Imutabilidade rasa:** `init` impede reatribuir referência, mas o conteúdo de um `string[]`/`List<T>` continua mutável.
- Propriedades **calculadas** em record: calcule no acesso (`=>`), não na inicialização (senão `with` produz valor errado).
- Atributos em record posicional usam alvo: `[property: JsonPropertyName("firstName")] string FirstName`.
- **Não use record como entidade do EF Core**: EF depende de igualdade por referência e não atualiza tipos imutáveis.

### 3. DTOs separados por finalidade
| Caso | DTO |
|---|---|
| Criar (POST) | sem `Id`, só campos que o cliente pode definir |
| Substituir (PUT) | todos os campos editáveis |
| Atualização parcial (PATCH) | propriedades **nullable** (`string?`, `bool?`) para distinguir "não enviado" |
| Resposta | só campos que o cliente pode ver |
| Admin | outro DTO, se precisar expor mais campos |

### 4. Mapeamento
- Entidade → DTO: construtor do DTO, método estático `ItemToDTO`, ou **projeção LINQ** `.Select(x => new TodoItemDTO(x))` (em EF Core projeta só as colunas necessárias; ver `efcore-querying`).
- DTO → entidade: crie a entidade copiando campo a campo permitido; no update, **carregue a entidade e copie apenas os campos permitidos** (nunca faça bind direto da entidade).
- A doc usa mapeamento manual; se usar biblioteca de mapeamento, ela não é coberta pela documentação oficial: avise o usuário.

### 5. Validação no DTO
`System.ComponentModel.DataAnnotations` (`[Required]`, `[Range]`...) em records/classes de entrada. Em Minimal APIs (.NET 10) a validação só roda se `builder.Services.AddValidation()` estiver registrado; com `[ApiController]` o 400 é automático (`ValidationProblemDetails`). Ver `aspnet-validation`, `aspnet-minimal-api`, `aspnet-controllers`.

### 6. Coleções e nullability
- Propriedades de coleção em DTO: inicialize (`= []`) e não retorne `null` (diretriz de coleções); ver `csharp-collections`.
- Habilite `<Nullable>enable</Nullable>`; `string?` = opcional, `string` = obrigatório (ver `csharp-nullable-references`).

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | Entidade de banco usada como parâmetro ou retorno do endpoint | Alta (overposting/vazamento) |
| 2 | DTO de entrada contém `Id`/campos de servidor que o cliente não deve definir | Alta |
| 3 | DTO de saída expõe campos sensíveis (`Secret`, hash, flags internas) | Alta |
| 4 | PATCH com propriedades não-nullable (perde "não enviado") | Média |
| 5 | PUT/POST sem validação (`[Required]`, `[Range]`) | Média |
| 6 | Update atribuindo o DTO inteiro à entidade (`entity = dto` / `Entry(...).State = Modified` com dado do cliente) | Alta |
| 7 | `record` usado como entidade EF | Média |
| 8 | Propriedade calculada inicializada no construtor em record usado com `with` | Baixa |
| 9 | Coleção `null` ou `List<T>` mutável exposta sem necessidade | Baixa |
| 10 | Leitura carregando entidade inteira só para montar DTO | Média (use projeção) |
| 11 | Um único DTO para criar, atualizar e ler com campos irrelevantes | Média |

## Fontes oficiais
- Tutorial Minimal API (DTO, PATCH com nullable): https://learn.microsoft.com/en-us/aspnet/core/tutorials/min-web-api
- Tutorial Web API controllers (overposting, `ItemToDTO`): https://learn.microsoft.com/en-us/aspnet/core/tutorials/first-web-api
- Records: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/record
- `required`: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/required
- Nullable reference types: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/null-safety/nullable-reference-types
- Validação em Minimal APIs: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/validation
