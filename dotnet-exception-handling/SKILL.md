---
name: dotnet-exception-handling
description: Implementar e revisar tratamento de exceções em C#/.NET - try/catch/finally, using, throw vs throw ex, ExceptionDispatchInfo, exceções customizadas, tipos predefinidos, ArgumentNullException.ThrowIfNull, Try* methods, OperationCanceledException, validação de argumentos em métodos async. Use quando o usuário pedir para revisar catch genérico, exceções engolidas, criar uma exceção customizada ou decidir entre exceção e retorno. Based on official Microsoft Learn docs.
---

# Exceções em C#/.NET — implementar e revisar

Só afirmar o que a doc oficial diz (fontes no fim). Para exceções em respostas HTTP, ver `aspnet-error-handling`.

## Tratando exceções
1. **`try/catch` só quando dá para se recuperar.** Se não dá, **não capture**: deixe quem está acima na pilha tratar. Ordene `catch` do tipo **mais derivado ao menos derivado**. Não capture `System.Exception` sem filtro de exceção (guideline de conventions: "só capture exceções que pode tratar de fato; evite exceções gerais").
2. **Libere recursos** com `using` (preferido, inclusive a forma sem chaves `using var x = ...;`) ou `finally` para o que não é `IDisposable`.
3. **Evite a exceção em condições comuns**: verifique antes (`if (conn.State != Closed)`), ou use métodos **`Try*`** (`int.TryParse`, `Dictionary.TryGetValue`). Use exceção para eventos realmente excepcionais; checagem em código quando é parte do fluxo normal. (Race condition entre checagem e operação ainda pode lançar.)
4. **Projete classes para evitar exceções**; retornar `null`/`default` (ou `Nullable<T>`) nos casos comuns de "não achou" é aceitável.
5. **Restaure estado** quando o método não completa por exceção: quem chama deve poder assumir "sem efeitos colaterais" (ex.: reverter o saque se o depósito falhar).
6. **Relançar corretamente:**
   - dentro do `catch`: `throw;` (preserva a stack trace). **Nunca `throw e;`** (reinicia a stack trace; regra de análise CA2200).
   - fora do `catch`: `ExceptionDispatchInfo.Capture(ex)` e depois `.Throw()`.
   - ou lance uma nova exceção **com a original como `innerException`**.
7. **Cancelamento/async:** capture `OperationCanceledException` (não `TaskCanceledException`, que deriva dela). Exceção em método async fica na `Task` e sai no `await`; **erros de uso (ex.: `ArgumentException`) saem de forma síncrona**.

## Lançando exceções
1. **Tipos predefinidos** primeiro: `InvalidOperationException` (estado inadequado), `ArgumentException` e derivadas (parâmetro inválido). **Não lance** tipos reservados: `AccessViolationException`, `IndexOutOfRangeException`, `NullReferenceException`, `StackOverflowException` (CA2201).
2. **Use os helpers estáticos de throw:** `ArgumentNullException.ThrowIfNull(x)`, `ArgumentException.ThrowIfNullOrEmpty/WhiteSpace`, `ArgumentOutOfRangeException.ThrowIfNegative/Zero/GreaterThan...`, `ObjectDisposedException.ThrowIf`, e `ct.ThrowIfCancellationRequested()` (CA1510–CA1513, CA2250).
3. **Mensagem** clara, gramática correta, terminando com ponto; localizada em apps localizados.
4. Coloque o `throw` onde a stack trace é útil. Crie *exception builder methods* se lança a mesma exceção em vários lugares.
5. **Não lance** em `finally` (CA2219), nem em `Equals`, `GetHashCode`, `ToString`, construtores estáticos, operadores de igualdade (CA1065).
6. **Validar argumentos antes** da parte assíncrona em métodos que retornam `Task`.

## Exceções customizadas
- Só crie quando não há tipo predefinido adequado. Nome termina em `Exception`, deriva de `Exception`.
- Inclua ao menos os 3 construtores: `()`, `(string message)`, `(string message, Exception inner)`.
- Propriedades extras só se houver cenário programático que use (ex.: `FileName` em `FileNotFoundException`).

```csharp
public class OrderNotFoundException : Exception
{
    public OrderNotFoundException() { }
    public OrderNotFoundException(string message) : base(message) { }
    public OrderNotFoundException(string message, Exception inner) : base(message, inner) { }
}
```

## Checklist de revisão
| # | Verificar | Gravidade |
|---|---|---|
| 1 | `catch (Exception)` vazio ou que só loga e segue (engole erro) | Alta |
| 2 | `throw ex;` em vez de `throw;` | Alta |
| 3 | `catch` de tipo base antes do derivado (não compila) / catch amplo sem filtro | Média |
| 4 | Recurso `IDisposable` sem `using` | Média |
| 5 | Exceção usada como controle de fluxo em caminho quente (`Parse` com `try/catch` em loop) → `TryParse` | Média |
| 6 | Lança `NullReferenceException`, `IndexOutOfRange`, `Exception` pura | Média |
| 7 | Validação de argumento lançada dentro do `async` (sai tarde) | Baixa |
| 8 | `catch (TaskCanceledException)` em vez de `OperationCanceledException` | Baixa |
| 9 | Exceção customizada sem os 3 construtores / sem sufixo `Exception` | Baixa |
| 10 | Mensagem sem ponto final/pouco clara | Baixa |
| 11 | Estado inconsistente após falha (sem rollback) | Alta |
| 12 | `throw` dentro de `finally` | Média |

## Fontes oficiais
- Best practices for exceptions: https://learn.microsoft.com/en-us/dotnet/standard/exceptions/best-practices-for-exceptions
- Design guidelines for exceptions: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/exceptions
- Coding conventions (try-catch e using): https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions
- Criar e lançar exceções: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/exceptions/creating-and-throwing-exceptions
