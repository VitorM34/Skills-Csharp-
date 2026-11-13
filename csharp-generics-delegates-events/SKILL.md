---
name: csharp-generics-delegates-events
description: Implementar e revisar generics, delegates, lambdas e eventos em C# - type parameters e constraints (where T : class/struct/new()/interface), covariância e contravariância, Func/Action, lambdas static, discards, padrão de eventos (EventHandler<T>, EventArgs, ?.Invoke), unsubscribe. Use quando o usuário pedir para criar tipos/métodos genéricos, callbacks, ou eventos, ou revisar vazamento por assinatura de evento. Based on official Microsoft Learn docs (C# fundamentals).
---

# Generics, delegates, lambdas e eventos

Só afirmar o que a doc oficial diz (fontes no fim). Coleções: `csharp-collections`. LINQ (lambdas em queries): `csharp-linq`.

## Generics
- Um código para qualquer tipo **com type safety**: o compilador verifica em tempo de compilação (sem casts em runtime nem `InvalidCastException`). Parâmetros de tipo: `T`, ou `TKey`/`TValue` (nomes descritivos com prefixo `T`; ver `csharp-coding-conventions`).
- **Sempre use coleções genéricas** (`System.Collections.Generic`), não as não genéricas (`ArrayList`): erros viram erros de compilação e **evitam boxing** em value types.
- **Métodos genéricos** declaram seu próprio parâmetro de tipo; o compilador costuma **inferir** o argumento de tipo.
- **Constraints:** `where T : class` (referência), `struct` (value type não nullable), `new()` (construtor público sem parâmetros), `BaseClass`, `IInterface`. (Tipo com membros `required` não pode satisfazer `new()`; ver `dotnet-model-review`.)
- **Variância:** **covariância** (`out T`): `IEnumerable<Dog>` onde se espera `IEnumerable<Animal>`; só em posições de **saída** (retorno). **Contravariância** (`in T`): `Action<Animal>` onde se espera `Action<Dog>`; só em posições de **entrada** (parâmetros).
- Collection expressions (C# 12): `List<string> l = ["a", "b"];`.

## Delegates e lambdas
- **Delegate** = tipo que representa referência a método; use **`Func<>`** (retorna valor; **o último parâmetro de tipo é o retorno**) e **`Action<>`** (sem retorno) em vez de declarar delegates próprios (convenção da doc, ver `csharp-coding-conventions`). O compilador verifica que a lambda casa com o delegate.
- Lambdas que **não capturam** nada: adicione **`static`** (não pode capturar locais nem estado da instância; evita closures/alocações acidentais).
- **Discards** (`_`) para parâmetros irrelevantes (handlers de evento, callbacks, overloads LINQ com índice não usado).
- C# 14: modificadores em parâmetros de lambda sem declarar tipos (`(text, out result) => ...`).
- Atenção a lambdas `async` convertidas para `Action` (viram `async void`): use `Func<Task>` (ver `csharp-async-await`).

## Eventos
- Evento = delegate com restrições: **fora da classe só se pode `+=`/`-=`; só a classe declarante dispara**. Convenção .NET: tipo **`EventHandler<T>`** com assinatura `(object? sender, T args)`.
- **Padrão (doc "Standard .NET event patterns"):**
  - retorno **`void`** (zero a muitos ouvintes; ouvintes não devolvem valor);
  - **`sender` do tipo `object`** (o remetente) e **`args`** derivado de `EventArgs` (use `EventArgs.Empty` se não há dados — *Event design guidelines*). No .NET moderno `EventHandler<TEventArgs>` **não exige mais** que `TEventArgs` derive de `EventArgs` (doc *The updated .NET Core event pattern*; mudar `FileFoundArgs` de class para struct quebraria o protocolo de cancelamento, pois ele depende de passagem por referência); o tipo de args deve ser **`class`** com propriedades **imutáveis** (um assinante não deve alterar os valores dos outros);
  - nome do evento = **verbo/frase verbal**: passado para algo que aconteceu (`Found`), presente para algo que vai acontecer (`Closing`);
  - declarar: `public event EventHandler<FileFoundArgs>? FileFound;` e disparar com **`FileFound?.Invoke(this, args)`** (**thread-safe**: o delegate é avaliado uma vez; só dispara se houver assinantes — fonte: *null-conditional operators* / *member access operators*, não a página de eventos).
- **Cancelamento/retorno de assinante:** comunique via campos em `EventArgs` (ex.: `CancelRequested`); decida se cancela com qualquer assinante ou só se todos pedirem.
- **Cuidado de ciclo de vida:** assinar cria **acoplamento** entre fonte e ouvinte; o ouvinte deve **cancelar a assinatura (`-=`)** quando não precisar mais (senão a fonte mantém o ouvinte vivo). Lambda anônima de handler só se **não precisará ser removida**.
- C# 14: eventos podem ser **partial** (declaração + implementação com `add`/`remove`).
- A doc também descreve padrões de delegates (`delegates-patterns`) e distinção delegate × evento; consulte antes de detalhar.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | `ArrayList`/`Hashtable`/`object` onde cabe generic |
| 2 | Constraint ausente/excessiva; variância `in`/`out` mal posicionada |
| 3 | Delegate customizado onde `Func`/`Action`/`EventHandler<T>` servem |
| 4 | Lambda `async` passada onde se espera `Action` |
| 5 | Evento sem verbo/convenção; `EventArgs` mutável; `sender` tipado errado |
| 6 | Disparo `Evento(this, args)` sem checar `null`/`?.Invoke` |
| 7 | Assinatura de evento sem desassinar (vazamento) |
| 8 | Lambda capturando variável/estado sem necessidade (usar `static`) |
| 9 | Evento público de classe `static` mantendo instâncias vivas (CONVENÇÃO: derivado do aviso de desassinatura, a doc não cita `static`) |

## Fontes oficiais
- Generics: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/types/generics
- Lambdas, delegates e events: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/types/delegates-lambdas
- Standard .NET event patterns: https://learn.microsoft.com/en-us/dotnet/csharp/event-pattern
- Introduction to events: https://learn.microsoft.com/en-us/dotnet/csharp/events-overview
- The updated .NET Core event pattern: https://learn.microsoft.com/en-us/dotnet/csharp/modern-events
- Event design (EventArgs.Empty): https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/event
- Null-conditional / thread-safe delegate invocation: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/member-access-operators
- Delegates overview: https://learn.microsoft.com/en-us/dotnet/csharp/delegates-overview
