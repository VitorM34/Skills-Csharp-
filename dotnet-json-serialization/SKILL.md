---
name: dotnet-json-serialization
description: Implementar e revisar serialização JSON com System.Text.Json em .NET/ASP.NET Core - JsonSerializerOptions (reuso, Web defaults, camelCase), JsonPropertyName, JsonIgnore, enums como string, required/RespectRequiredConstructorParameters, nullable annotations, tipos imutáveis/records, polimorfismo, membros ausentes, source generation, migração do Newtonsoft. Use quando o usuário pedir para configurar JSON na API, controlar nomes/propriedades, deserializar records ou revisar desempenho de serialização. Based on official Microsoft Learn docs.
---

# JSON com System.Text.Json

Só afirmar o que a doc oficial diz (fontes no fim); itens marcados com versão (ex.: .NET 11) **não se aplicam a .NET 10**. DTOs: `dotnet-dto-review`. Endpoints: `aspnet-http-endpoints`.

## Opções (reuse!)
- **Reuse a mesma instância de `JsonSerializerOptions`** em todas as chamadas (inclusive em conversores customizados): criar uma nova a cada uso causa **problemas de desempenho** (caches de metadata por instância). É thread-safe. Use `JsonSerializerOptions.Default` quando os padrões bastam.
- **Web defaults** (padrão do ASP.NET Core: camelCase, case-insensitive, números como string permitidos): `JsonSerializerOptions.Web` (.NET 9+) ou `new JsonSerializerOptions(JsonSerializerDefaults.Web)`. **Minimal APIs usam web defaults**; configure globalmente com `builder.Services.ConfigureHttpJsonOptions(o => ...)`; MVC com `AddJsonOptions` no formatter de entrada/saída.
- Padrões do `JsonSerializer` **fora** do ASP.NET: nomes inalterados (case preservado), match de propriedade **case-sensitive**, enums como **números**, campos ignorados, **comentários e vírgulas finais lançam exceção**, profundidade máxima **64**, propriedades na ordem de declaração, propriedades JSON não mapeadas **são ignoradas**.

## Nomes, enums e ordem
- `[JsonPropertyName("x")]` por membro; política global `PropertyNamingPolicy` (ex.: `JsonNamingPolicy.CamelCase`). Precedência: atributo no membro > política. `DictionaryKeyPolicy` só afeta **serialização**.
- **Enums como string:** `JsonStringEnumConverter` (ou o genérico `JsonStringEnumConverter<T>`, **único suportado em Native AOT**) via `[JsonConverter]` ou options. `[JsonPropertyOrder(n)]` controla a ordem (padrão 0).
- Source generation **não executa política de nomes customizada**: usa o nome CLR.

## Ignorar propriedades
`[JsonIgnore]` (Condition: `Always` padrão, `Never`, `WhenWritingDefault`, `WhenWritingNull`); globais: `IgnoreReadOnlyProperties` (coleções read-only ainda são serializadas), `DefaultIgnoreCondition`. (Condição no nível do tipo é .NET 11.)

## Required e nulls
- **Required:** `required` do C#, `[JsonRequired]` ou `JsonPropertyInfo.IsRequired`; falta → `JsonException` na deserialização. `required` e `[JsonRequired]` são equivalentes para o serializador; **use `[JsonRequired]`** quando o requisito deve valer só para JSON ou com **source generation modo metadata** (o `required` do C# não compila nesse modo). `JsonSerializerOptions.RespectRequiredConstructorParameters` (.NET 9+) trata parâmetros de construtor **não opcionais** como obrigatórios (**recomendado em apps novos**).
- **Nullable annotations:** `JsonSerializerOptions.RespectNullableAnnotations` (.NET 9+; recomendado em apps novos) impõe `string` vs `string?` na deserialização. Limitações: `MyPoco` e `MyPoco?` são indistinguíveis em IL; **propriedade ausente não é erro** (fica no valor padrão), enquanto `null` explícito viola não-nullable; required e non-nullable são conceitos **ortogonais**. .NET não tem `undefined`: ausente e `null` viram `null`.
- Membros desconhecidos: por padrão ignorados; a partir do .NET 8 dá para exigir que todos existam (`JsonUnmappedMemberHandling.Disallow` via `[JsonUnmappedMemberHandling]` no tipo ou `JsonSerializerOptions.UnmappedMemberHandling` → `JsonException`).

## Tipos imutáveis, records, construtores
- Padrão: construtor **público sem parâmetros**. Construtor parametrizado: se for o **único** em uma classe, é usado; em struct ou classe com vários, use **`[JsonConstructor]`**. Nomes dos parâmetros devem casar com as propriedades (case-insensitive) **pelo nome real da propriedade, mesmo com `[JsonPropertyName]`**. **Records posicionais** são suportados. Propriedades `init` são deserializadas como setters normais. Read-only (sem setter) deserializam a partir do .NET 8 com `JsonObjectCreationHandling.Populate`.
- Membros não públicos: source generation (até .NET 10) **não suporta `private/protected`**; `internal` só no mesmo assembly do contexto.

## Polimorfismo
`[JsonPolymorphic]` + `[JsonDerivedType(typeof(X), "discriminador")]` na **base**; para deserializar precisa de **discriminador** (`$type` por padrão, deve vir **no início** do objeto, ou `AllowOutOfOrderMetadataProperties = true`). Serialize usando o **tipo base** como tipo genérico/declarado. Evite misturar discriminadores `string` e `int`; evite nome de discriminador que conflite com propriedade. Tipos derivados desconhecidos: opt-in por anotação na base.

## Source generation × reflexão
- Padrão: **reflexão** em runtime (coleta e cacheia metadata na primeira vez: custa tempo e memória). **Source generation** (C# 9+) melhora desempenho, reduz memória e **viabiliza trimming/Native AOT**. Use `JsonSerializerContext` + `[JsonSerializable(typeof(T))]`; membros `object` precisam do tipo de runtime declarado; modos *metadata* e *serialization optimization* (fast-path; não para serialização assíncrona). Desabilite reflexão (`JsonSerializerIsReflectionEnabledByDefault=false`) para detectar quebras de AOT cedo.
- `HttpClient` tem extensões (`GetFromJsonAsync`, `PostAsJsonAsync`, `ReadFromJsonAsync`): ver `dotnet-httpclient-resilience`.
- Extension data/overflow: `[JsonExtensionData]` com `Dictionary<string, JsonElement>`; `JsonElement`/`JsonNode` para JSON dinâmico (`JsonDocument`/DOM, `Utf8JsonReader/Writer` para alto desempenho).

## Migração do Newtonsoft.Json
`System.Text.Json` foca em **desempenho, segurança e conformidade**, **sem paridade total**. Diferenças: case-sensitive por padrão (`PropertyNameCaseInsensitive`), sem aspas simples/sem aspas em nomes (✖ por design), `JsonConvert.PopulateObject`, `DateTimeZoneHandling`/`DateFormatString`, deserializar para `object` inferindo tipo, `null` em tipo valor não-nullable → ⚠ exigem **conversores customizados**. Tabela completa na doc.

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | `new JsonSerializerOptions` dentro de método chamado repetidamente |
| 2 | Opções JSON da API (camelCase/enum string) definidas globalmente (`ConfigureHttpJsonOptions`/`AddJsonOptions`) |
| 3 | DTOs de entrada com `required`/validação; `RespectNullableAnnotations`/`RespectRequiredConstructorParameters` habilitados em app novo |
| 4 | Records/construtores parametrizados com nomes compatíveis; `[JsonConstructor]` quando há mais de um |
| 5 | Enums expostos como número sem querer |
| 6 | Polimorfismo sem discriminador, ou serializando pelo tipo derivado |
| 7 | Dados sensíveis serializados (usar `[JsonIgnore]` ou DTO) |
| 8 | Native AOT/trimming sem source generation |
| 9 | Dependência de comportamento do Newtonsoft sem conversor equivalente |

## Fontes oficiais
- Overview: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/overview
- Configure options: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/configure-options
- Customize properties: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/customize-properties
- Ignore properties: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/ignore-properties
- Required properties: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/required-properties
- Nullable annotations: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/nullable-annotations
- Immutable types: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/immutability
- Polymorphism: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/polymorphism
- Source generation: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/source-generation
- Missing members: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/missing-members
- Migrar do Newtonsoft: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/migrate-from-newtonsoft
- Minimal APIs (JSON): https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/responses
