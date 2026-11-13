---
name: dotnet-framework-design-guidelines
description: Revisar o design de APIs e tipos .NET segundo as Framework Design Guidelines - nomenclatura (tipos, membros, parâmetros, namespaces), design de tipos (struct, enum, classes abstratas/estáticas/aninhadas), membros (propriedades, construtores, campos, overloads, parâmetros, extension methods, operadores), extensibilidade (sealing, virtual, protected), eventos, atributos, arrays, igualdade, exceções. Use quando o usuário pedir revisão de design de API pública/biblioteca ou dúvidas "o certo segundo o .NET". Based on official Microsoft Learn docs (Framework Design Guidelines, 2ª edição; parte pode estar desatualizada).
---

# Framework Design Guidelines — revisão de API

Fonte: *Framework Design Guidelines* (Cwalina/Abrams, 2ª edição, 2008, reproduzidas na doc da Microsoft; a própria doc avisa que **partes podem estar desatualizadas** e que o livro foi revisado numa 3ª edição). São diretrizes para **bibliotecas reutilizáveis**; em código de aplicação, aplique com bom senso e respeite o `.editorconfig` do projeto. Convenções de codificação do dia a dia: `csharp-coding-conventions` (note que as duas fontes divergem em pontos como prefixo `_` em campos privados: as FDG tratam de API **pública**, onde campos não devem ser públicos). Notação: ✔ DO / ✖ DO NOT / ~ AVOID / ? CONSIDER.

## Nomenclatura
**Capitalização:** PascalCase em tipos, membros públicos e namespaces; camelCase em parâmetros. Não capitalize cada palavra de palavras compostas "fechadas". **Nomes não podem diferir só por maiúsculas** (nem toda linguagem é case-sensitive).
**Palavras:** ✔ nomes legíveis; ✔ legibilidade acima de brevidade; ✖ underscores/hífens/não alfanuméricos; ✖ notação húngara; ~ conflito com palavras-chave de linguagens; ✖ abreviações/contrações; ✖ acrônimos pouco aceitos; ✔ nomes semânticos em vez de nomes de tipo da linguagem (use nome CLR genérico ou `value`/`item` quando o nome não tem significado). **Novas versões de API:** nome semelhante, **sufixo** (não prefixo), numérico se for padrão de mercado, sufixo `64` para versões de `long`; ✖ sufixo `Ex`.
**Tipos:** classes/structs = **substantivo/frase nominal**; interfaces = **adjetivo** (ou substantivo), **prefixo `I`**; ✖ prefixo `C`; ? terminar derivadas com o nome da base; par classe–interface difere só pelo `I`. Genéricos: nomes descritivos com prefixo `T` (ou `T` único), ? indicar restrição no nome. Sufixos: `Attribute`, `EventHandler` (delegates de evento), `Callback` (outros delegates; ✖ sufixo `Delegate`), `EventArgs`, `Exception`, `Dictionary`, `Collection`, `Stream`; ✖ sufixos `Enum`/`Flag` em enums.
**Namespaces:** prefixo da empresa, produto estável no 2º nível, PascalCase com pontos; ✖ hierarquia organizacional; ✖ mesmo nome para namespace e tipo; ✖ nomes genéricos de tipos (`Element`, `Node`, `Log`, `Message`) e conflitos com tipos de namespaces core.
**Membros:** métodos = **verbo/frase verbal**; propriedades = substantivo/adjetivo (✖ propriedade com mesmo nome de método `Get...`); coleções no **plural**; booleanas **afirmativas** (`CanSeek`, com `Is/Can/Has` só se agrega); eventos = verbo, **passado/presente** (✖ prefixos `Before/After`), handlers com `sender` e `e`; campos PascalCase, ✖ prefixo. Parâmetros: camelCase descritivos, nomes pelo significado; operadores: `left`/`right`, `value`.

## Design de tipos
- ✔ cada tipo = conjunto bem definido de membros relacionados.
- **Class × struct:** ? struct se a instância é pequena, curta e embutida em outros objetos; ~ struct **a menos que** tenha **todas**: representa **um único valor** (como primitivos), **instância < 16 bytes**, é **imutável**, **não sofrerá boxing com frequência**. Struct: ✖ construtor sem parâmetros (**texto de 2008**; a doc atual de structs em C# descreve construtores sem parâmetros em structs — ver `csharp-types-oop`); ✖ tipos de valor mutáveis; ✔ estado zerado/`null`/`false` deve ser válido; ✔ implemente `IEquatable<T>`.
- **Enums:** ✔ use enum em vez de constantes; ✖ conjuntos abertos; ✖ valores reservados para o futuro ou sentinelas; ~ enum público com um só valor; ✔ valor **zero** em enums simples; ? `Int32` como base; nomes: **plural** em flags, **singular** em simples. **Flags:** ✔ `[Flags]` (só em flags), **potências de 2**, ? valores para combinações comuns, ~ combinações inválidas, zero chamado **`None`**. ? adicionar valores a enums publicados (risco pequeno).
- **Classe abstrata:** ✖ construtores `public`; ✔ `protected`/`internal`; ✔ ao menos uma implementação concreta. **Estática:** usar com parcimônia, ✖ "balaio de gatos", ✖ membros de instância. **Aninhados:** só se a relação pede semântica de acessibilidade; ✖ aninhados públicos como agrupamento (use namespaces); ✖ se serão instanciados por clientes ou referenciados fora.
- **Abstrações:** ✖ só crie abstração (interface/abstract class) se **testada** por várias implementações concretas e APIs consumidoras; ? testes de referência para implementações; base classes ? `abstract`, em namespace separado, ~ sufixo `Base` em API pública.

## Design de membros
- **Propriedades:** ✔ get-only se o chamador não deve alterar; ✖ set-only ou setter mais amplo que o getter; ✔ valores padrão sensatos; ✔ permitir ordem qualquer de atribuição (estado temporariamente inválido); ✔ preservar valor anterior se o setter lança; ~ lançar exceção em getter. Indexadores: ? em coleções; ~ mais de um parâmetro.
- **Construtores:** ? simples (idealmente padrão); ? **factory estática** se a semântica não mapeia a "criar instância"; ✔ parâmetros como atalho para propriedades principais (mesmo nome); ✔ **pouco trabalho**; ✔ lançar exceção se apropriado; ~ chamar **membros virtuais** no construtor; construtor estático `private`.
- **Campos:** ✖ campos de instância públicos/protegidos; ✔ `const` para constantes imutáveis; ✔ `public static readonly` para instâncias predefinidas; ✖ tipos mutáveis em `readonly`.
- **Parâmetros:** ✔ tipo **menos derivado** que atende; ✔ `out` por último; ✔ validar argumentos de membros públicos/protegidos (`ArgumentException`/`ArgumentNullException`; validar enums; ✖ `Enum.IsDefined` para range; argumentos mutáveis podem mudar após validação); ✔ **enum em vez de 2+ booleanos**; ✖ booleano se pode vir a ter mais de dois valores; ~ `out`/`ref`; ✖ passar tipos de referência por `ref`; `params`: ? em arrays de poucos elementos, ~ se o chamador quase sempre já tem array, ✖ se o método modifica o array, ✔ lembrar que `null` pode ser passado.
- **Overloads:** nomes de parâmetros consistentes e mesma ordem; só o **overload mais longo** é virtual; ✖ `ref/out` para diferenciar; ✔ permitir `null` em opcionais; ✔ **overloads em vez de argumentos default** (nas FDG; no C# moderno, considere o impacto de versionamento).
- **Extension methods:** ~ definir levianamente, sobretudo em tipos que não são seus; ~ em `object`; ✖ no mesmo namespace do tipo estendido (exceto interfaces/gestão de dependências); ~ namespaces genéricos "Extensions".
- **Operadores:** ~ sobrecarregar exceto em tipos que devem "parecer primitivos"; ✔ em structs numéricas; ✖ "ser esperto"; ✔ simetria; ? método com nome amigável equivalente; **conversões:** ✖ implícitas se com perda, ✖ lançar em cast implícito.
- **Igualdade:** ✖ sobrecarregar só um dos operadores `==`/`!=`; ✔ `Equals` e operadores com a mesma semântica; ~ lançar exceção; ✔ sobrecarregar em value types; ~ em reference types mutáveis ou mais lentos que referência.

## Extensibilidade
- ✖ **selar sem bom motivo**; ✖ membros `protected`/`virtual` em tipos selados; ? selar membros que você sobrescreve; ? **classes não seladas sem membros virtuais/protegidos** = extensibilidade barata.
- ✖ **`virtual` sem boa razão** (custos de design, teste e manutenção); ? limitar ao estritamente necessário; ✔ prefira `protected` a `public` para virtuais (membro público chama um protegido virtual).
- ✔ tratar membros `protected` de classes não seladas **como públicos** para segurança/documentação/compatibilidade.
- **Callbacks e eventos:** ? callbacks para código customizado; ✔ **eventos preferidos a callbacks simples**; ~ callbacks em APIs sensíveis a desempenho; ✔ `Func/Action/Expression` em vez de delegates customizados; medir `Expression<>`; lembrar que chamar delegate executa código arbitrário.
- **Eventos:** ✔ dizer "**raise**" (não fire/trigger); ✔ `EventHandler<T>`; ? subclasse de `EventArgs`; ✔ **método `protected virtual` para disparar** (eventos não estáticos em classes não seladas); ✖ `null` como `sender` em evento não estático (✔ `null` em estático); ✖ `null` como dados do evento; ? eventos cancelável (pré-eventos); handlers: retorno `void`, `object sender`, `EventArgs e`, **no máximo 2 parâmetros**.

## Atributos, arrays, serialização, exceções
- **Atributos:** sufixo `Attribute`; `AttributeUsage`; propriedades **settable** para argumentos opcionais, **get-only** + parâmetro de construtor para obrigatórios; ~ overload de construtores; ✔ **selar** (lookup mais rápido).
- **Arrays:** ✔ **coleções em vez de arrays em APIs públicas** (ver `csharp-collections`); ✖ campos array `readonly` (elementos mutáveis); ? jagged em vez de multidimensional.
- **Serialização:** pense nela ao desenhar tipos; a doc cita Data Contract/XML/Runtime (JSON moderno: `dotnet-json-serialization`).
- **Exceções:** ✖ retornar códigos de erro; ✔ reportar falhas lançando; ✖ exceção para fluxo normal; taxas > ~100/s afetam desempenho; ✔ documentar exceções; ✖ membro que lança ou não conforme opção; ✖ lançar de filtros; ~ lançar de `finally`; ✖ lançar/derivar `ApplicationException`; ✖ lançar `Exception`/`SystemException`; ~ capturar `Exception` exceto em handlers de topo; ✔ `InvalidOperationException` para estado inadequado; ✔ `ArgumentException` (mais derivada) com `ParamName`; ✖ expor `NullReferenceException`/`IndexOutOfRange`/`AccessViolation`; ✖ lançar `StackOverflow`/`OutOfMemory`/`COMException`. Ver `dotnet-exception-handling`.

## Checklist de revisão (API pública)
1. Nomes seguem as regras (substantivo/verbo/adjetivo, sufixos, sem abreviações, sem prefixos em campos/classes).
2. Struct realmente atende as 4 condições; enum com `None`/zero e potências de 2.
3. Abstrações têm implementação concreta e consumidor; classes abstratas com construtor protegido.
4. Propriedades simples e baratas; construtores com pouco trabalho e sem virtuais.
5. Parâmetros validados; enums em vez de múltiplos booleanos; sem `ref/out` desnecessário.
6. Virtual/protected só com razão; classes seladas quando não projetadas para herança (e membros sobrescritos selados).
7. Eventos: `EventHandler<T>`, `raise` via método protegido, `sender/e`, sem `null`.
8. Coleções (e não arrays/`List<T>`) na superfície pública; `==`/`Equals`/`GetHashCode` consistentes.

## Fontes oficiais
- Framework Design Guidelines (índice): https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/
- Naming: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/naming-guidelines
- Capitalization: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/capitalization-conventions
- Type design: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/type
- Choosing between class and struct: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/choosing-between-class-and-struct
- Enum design: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/enum
- Member design: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/member
- Parameter design: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/parameter-design
- Designing for extensibility: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/designing-for-extensibility
- Event design: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/event
- Exceptions: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/exceptions
- Usage guidelines: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/usage-guidelines
