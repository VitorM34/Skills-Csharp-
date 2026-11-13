---
name: aspnet-validation
description: Implementar e revisar validação de entrada no ASP.NET Core - DataAnnotations ([Required], [Range], [StringLength]), AddValidation() em Minimal APIs (.NET 10), validação em controllers com [ApiController]/ModelState, atributos customizados, IValidatableObject, objetos aninhados, SkipValidation, non-nullable implícito como Required. Use quando o usuário pedir para validar DTOs/requests, ou perceber que a validação não está rodando. Based on official Microsoft Learn docs (ASP.NET Core 10).
---

# Validação de entrada no ASP.NET Core

Só afirmar o que a doc oficial diz (fontes no fim). DTOs: `dotnet-dto-review`. Erros 400: `aspnet-error-handling`.

## Minimal APIs (.NET 10): precisa registrar
```csharp
builder.Services.AddValidation();   // Microsoft.Extensions.Validation
public record Product([Required] string Name, [Range(1, 1000)] int Quantity);
```
- **Sem `AddValidation()` NENHUMA validação automática roda**: a entrada inválida chega ao handler, sem exceção nem log. (Checklist #1 de revisão.)
- Validação acontece **antes** do handler, para query, header e corpo; falha → `400` com detalhes (customizar via `IProblemDetailsService`). Desligar por endpoint: `.DisableValidation()`.
- Usa **source generator** que gera metadados para os tipos validáveis no assembly onde `AddValidation` é chamado. Para tipos em **outro assembly** há registro específico (ver "Register validation across assemblies"). Falta de metadados não gera exceção.
- Tipos de modelo **não** podem ser declarados em arquivos `.razor`; declare em `.cs`.
- Objetos aninhados/coleções: anote o tipo raiz com `[ValidatableType]` (tipos alcançáveis são descobertos). Em apps .NET 10, `ValidatableTypeAttribute` e `SkipValidationAttribute` (pacote `Microsoft.Extensions.Validation`) são **experimentais** (aviso ASP0029; pode suprimir com `NoWarn`).
- `[SkipValidation]` em propriedade, parâmetro ou tipo ignora validação.
- Limitação conhecida antes do .NET 11: tipos de valor nullable como parâmetros de Minimal API **não** são validados.
- Ordem de validação do modelo: (1) atributos de cada propriedade e depois o valor (se `IEnumerable`, cada elemento não nulo); erro → pula o resto; (2) atributos no tipo; (3) `IValidatableObject.Validate`.
- Esta API **não** é suportada em MVC/Razor Pages (use a validação do MVC).

## Controllers (MVC) com `[ApiController]`
- `[ApiController]` dispara **400 automático** quando `ModelState` é inválido (resposta `ValidationProblemDetails`); `if (!ModelState.IsValid)` é redundante.
- **Non-nullable implica `[Required(AllowEmptyStrings = true)]`** quando `<Nullable>enable</Nullable>`: `string Name` ausente no JSON/form gera erro de validação (porque string vazia vira `null` por padrão). Use `string?` para opcional. Desligar: `SuppressImplicitRequiredAttributeForNonNullableReferenceTypes = true`.
- No servidor, "required" = valor nulo; tipo não-nullable (ex.: `decimal`) sempre "válido" para `[Required]`, mas o binding pode falhar com `The value '' is invalid`: torne nullable (`decimal?`) ou configure a mensagem padrão do model binding.
- No cliente, whitespace passa no `required` do jQuery Validation, enquanto o servidor rejeita string só de espaços.
- Mensagens: `ErrorMessage = "..."`; placeholders `{0}` = nome do campo etc. (`[StringLength(8, ErrorMessage = "{0} length must be between {2} and {1}.", MinimumLength = 6)]`).
- Também existem `[Remote]`, validação client-side (unobtrusive), `ValidationResult`, limites de erros máximos/recursão.

## Regras customizadas
- **Atributo customizado:** herde de `ValidationAttribute` e sobrescreva `IsValid(object? value, ValidationContext ctx)`; retorne `ValidationResult` com mensagem em caso de erro. Para resolver serviços da DI use `validationContext.GetService<T>()` (ou `GetRequiredService<T>()`) — o serviço precisa estar registrado.
- **Validação de classe:** implemente `IValidatableObject` (`Validate(ValidationContext)` retornando `ValidationResult`s). O atributo customizado serve a um tipo específico; `IValidatableObject` é a opção de nível de classe.
- No .NET 11 há validação assíncrona (`IAsyncValidatableObject`) e localização de mensagens; **não** assuma isso em projetos .NET 10.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | Minimal API sem `AddValidation()` → validação não roda |
| 2 | DTO de entrada sem atributos de validação |
| 3 | Tipo validado declarado em `.razor` ou em outro assembly sem registro |
| 4 | Aninhados/coleções sem `[ValidatableType]` na raiz |
| 5 | Controller sem `[ApiController]` e sem checar `ModelState` |
| 6 | Nullability errada: opcional como `string` (erro 400 inesperado) ou obrigatório como `string?` sem `[Required]` |
| 7 | Regra de negócio complexa dentro de atributo/handler em vez de service |
| 8 | Atributo customizado dependendo de serviço não registrado |
| 9 | Validar só no cliente |
| 10 | Mensagens expondo detalhes internos |

## Fontes oficiais
- Validation in ASP.NET Core (Minimal APIs/Blazor, .NET 10+): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/validation
- Model validation in MVC and Razor Pages: https://learn.microsoft.com/en-us/aspnet/core/mvc/models/validation
- Minimal APIs (validation support): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis#validation-support-in-minimal-apis
- DataAnnotations: https://learn.microsoft.com/en-us/dotnet/api/system.componentmodel.dataannotations
