---
name: csharp-types-oop
description: Escolher e revisar tipos e orientação a objetos em C# - class vs struct vs record vs enum, construtores (primary, required, object initializers), classes estáticas, herança, virtual/override/abstract/sealed/new, polimorfismo, igualdade (valor vs referência, Equals/GetHashCode, ReferenceEquals), enums e [Flags]. Use quando o usuário pedir para modelar tipos, revisar herança/polimorfismo, decidir class vs struct ou corrigir bugs de igualdade. Based on official Microsoft Learn docs (C# fundamentals).
---

# Tipos e orientação a objetos em C#

Só afirmar o que a doc oficial diz (fontes no fim). Records/`required`: `dotnet-model-review`. Interfaces: `dotnet-interface-review`. Diretrizes de design de API: `dotnet-framework-design-guidelines`.

## Class × struct × record × enum
| Tipo | Quando (doc) |
|---|---|
| **class** (referência) | instâncias representam **identidade compartilhada**, não valores iguais; duas referências ao mesmo objeto ficam em sincronia; suporta **herança**. Acesso padrão: `internal` (use `public` para outros assemblies). |
| **struct** (valor) | tipo **pequeno** (a doc diz "cerca de 16 bytes ou menos") cujo papel é guardar dados, sem modelar comportamento; **semântica de valor** (duas instâncias com os mesmos dados são iguais); **sem herança** (só implementa interfaces). Atribuição **copia** tudo. |
| **record** | dados imutáveis com igualdade por valor (ver `dotnet-model-review`) |
| **enum** | valor deve ser um de um conjunto **fixo**; base `int` por padrão (valores 0,1,…); use em `switch` expression (o compilador avisa itens não tratados); `[Flags]` para combinações (e `ToString()` lista `Read, Write`); prefira `TryParse` a `Parse` para entrada possivelmente inválida |

### Structs: detalhes da doc
- `new T()` roda o construtor sem parâmetros (pode ter lógica); **`default(T)` ignora o construtor** e zera os campos (`0`, `null`, `false`). Campos não atribuídos no construtor são inicializados automaticamente.
- **`readonly struct`** garante que nenhum membro altera estado (campos e auto-properties read-only); ou marque membros `readonly` individualmente.
- Plain structs **não ganham `==`** automaticamente; se definir `==`/`!=`, faça par e mantenha consistente com `Equals`/`GetHashCode`. Tuplas são value types; nomes dos elementos **não** entram na comparação, só posição e valor.

### Classes: construtores e inicialização
- Opções: **field initializers**, parâmetros de construtor (obrigam o chamador a fornecer), **primary constructors** (C# 12), **`required`** (obriga via object initializer), **object initializers** (qualquer propriedade com `set` ou `init`).
- **Classe estática:** não instancia, só membros estáticos, **implicitamente `sealed`**; para utilitários sem estado de instância (ex.: `Math`).

## Herança e polimorfismo
- Herança + encapsulamento + polimorfismo = 3 pilares da OO. Uma classe deriva de **uma** base (todas derivam de `System.Object`); **construtores não são herdados**; structs não herdam mas implementam interfaces. Interfaces podem ter implementação default herdada por derivadas.
- **`virtual`** permite `override` na derivada; **`abstract`** **obriga** `override` em toda classe **não abstrata** derivada; classe `abstract` não pode ser instanciada.
- **Polimorfismo:** a derivada só sobrescreve membro `virtual` ou `abstract` e **deve usar `override`**. Só **métodos, propriedades, eventos e indexadores** podem ser virtuais (**campos não**). Ao sobrescrever, o membro da derivada é chamado **mesmo via referência do tipo base**.
- **`new`** esconde membro da base (oculta, não sobrescreve); **`sealed override`** impede novas sobrescritas.
- **Recomendação da doc:** membros virtuais devem chamar **`base`** na sua implementação para preservar o comportamento da base; se não chamar, a derivada é responsável por manter a compatibilidade.
- Classe abstrata (estado/construtores/membros não públicos compartilhados) × interface (capacidades entre hierarquias): ver `dotnet-interface-review`.

## Igualdade (doc "Equality comparisons")
- **Igualdade de valor** (dados iguais) × **de referência** (mesmo objeto). Padrão: value types comparam dados; reference types comparam identidade (autor do tipo pode mudar). **Records comparam por valor.**
- `Object.ReferenceEquals` sempre testa identidade, **independente** de overrides/`==`; use-o dentro de `Equals` para curto-circuito; retorna **`false` para value types** (boxing separado).
- Ao sobrescrever `Equals`, **sobrescreva `GetHashCode` junto** e mantenha `==`/`!=` consistentes. Prefira `is null`/`is not null` a `== null` (o operador `==` pode ser sobrecarregado).

## Checklist de revisão
| # | Verificar |
|---|---|
| 1 | `struct` grande/mutável ou com semântica de identidade → usar class |
| 2 | `struct` usado onde `default` pode produzir estado inválido (campos de referência `null`) |
| 3 | Herança usada para reaproveitar código sem relação "é um" (preferir composição/interface) |
| 4 | Método sobrescrito sem chamar `base` quando a base tem comportamento essencial |
| 5 | `new` escondendo membro por engano em vez de `override` |
| 6 | `Equals` sobrescrito sem `GetHashCode`; `==` inconsistente com `Equals` |
| 7 | Classe não destinada à herança sem `sealed` (apenas se fizer sentido; ver design guidelines) |
| 8 | Enum sem valor `0` significativo (diretriz FDG de enums: "DO provide a value of zero"; em `[Flags]` o zero deve ser `None`); `[Flags]` sem potências de 2 (doc de enums) |
| 9 | Propriedades públicas mutáveis onde deveria haver `init`/`required`/construtor |
| 10 | Classe estática usada para guardar estado global mutável |

## Fontes oficiais
- Classes: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/types/classes
- Structs: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/types/structs
- Enums: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/types/enums
- Inheritance: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/object-oriented/inheritance
- Polymorphism: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/object-oriented/polymorphism
- Equality: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/expressions/equality
- Records: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/record
- Enum design (valor zero, None): https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/enum
