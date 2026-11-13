---
name: csharp-nullable-references
description: Implementar e revisar nullable reference types em C# (<Nullable>enable</Nullable>, string vs string?, null-state analysis, operador !, atributos NotNullWhen, avisos CS8600-CS8625, propriedades required, armadilhas de struct default e arrays). Use quando o usuário pedir para corrigir warnings de null, habilitar nullable ou revisar se propriedades/parâmetros estão com nullability correta. Based on official Microsoft Learn docs.
---

# Nullable reference types — implementar e revisar

Só afirmar o que a doc oficial diz (fontes no fim).

## O que é
Recurso **só de compilação**: reduz `NullReferenceException` mostrando avisos quando a declaração de intenção (`string` vs `string?`) não bate com o uso. O comportamento em runtime não muda; `string` e `string?` são o mesmo tipo.

Três blocos: **anotações** (`?`), **análise de estado nulo** (not-null / maybe-null por expressão) e **atributos** em APIs.

## Habilitar
Templates recentes já trazem. Em projeto antigo, no `.csproj`:
```xml
<Nullable>enable</Nullable>
```
Migração gradual: ver *nullable migration strategies*.

## Regras
1. Todo reference type é **não-nulo por padrão**; `?` declara que pode ser nulo.
2. Variável não-nula: aviso se receber valor possivelmente nulo. Variável nullable: aviso se for **desreferenciada** sem checar.
3. A análise se atualiza por **atribuição** e por **checagens** (`is null`, `is not null`, `is { }`, `if`, loops, retorno antecipado). Ela **não entra no corpo de outros métodos**: use atributos para comunicar contrato.
4. Tipo de modelagem: obrigatório = não-nulo (`FirstName`), opcional = nullable (`MiddleName`). Construtor deixando membro não-nulo sem inicializar gera aviso. Alternativas: parâmetro de construtor primário, ou `required` (ver `dotnet-dto-review`).
5. **Operador `!`** (null-forgiving): afirma not-null ignorando a análise. Use com parcimônia: cada uso é um ponto sem proteção. Prefira checagem de null, reestruturar ou anotar a API.
6. **Atributos** (`System.Diagnostics.CodeAnalysis`): ex. `[NotNullWhen(true)] string? value` para métodos tipo `IsPresent(value)` que, ao retornar `true`, garantem not-null. Todas as APIs do .NET são anotadas desde o .NET 5.

## Armadilhas documentadas (sem aviso do compilador)
- **`default`/`new()` de struct** deixa campos de referência não-nulos como `null`. Use `required` ou construtor parametrizado.
- **`new string[3]`** cria elementos `null`. Inicialize junto: collection expression `["a","b","c"]` ou `new()` target-typed. Vale também para arrays de structs.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | `<Nullable>enable</Nullable>` presente |
| 2 | Obrigatório vs opcional refletidos (`string` / `string?`) em entidades, DTOs e parâmetros |
| 3 | Uso de `!` sem justificativa (ou espalhado) |
| 4 | `#nullable disable` / `#pragma warning disable CS86xx` cobrindo problema real |
| 5 | Retorno `null` de método com tipo não-nulo, ou retorno nullable não documentado |
| 6 | Propriedade não-nula sem inicialização (`= default!` como atalho): preferir `required`/construtor |
| 7 | Dereferência de resultado de `FindAsync`, `FirstOrDefault`, `TryGetValue` sem checar |
| 8 | Arrays/structs default com campos de referência |
| 9 | Métodos `TryX` sem `[NotNullWhen(true)]` quando o contrato exige |

## Fontes oficiais
- Nullable reference types: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/null-safety/nullable-reference-types
- Atributos de análise nula: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/attributes/nullable-analysis
- Estratégias de migração: https://learn.microsoft.com/en-us/dotnet/csharp/advanced-topics/update-applications/nullable-migration-strategies
- `required`: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/required
