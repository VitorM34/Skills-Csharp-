---
name: csharp-collections
description: Escolher e revisar coleções em C# (List<T>, Dictionary, HashSet, Queue, Stack, IEnumerable<T>, IReadOnlyList, ReadOnlyCollection, arrays, coleções imutáveis e concorrentes) e o que expor em APIs públicas, propriedades e parâmetros. Use quando o usuário perguntar qual coleção usar, se retornar List<T> está certo, null vs coleção vazia, ou revisar assinaturas com coleções. Based on official Microsoft Learn docs.
---

# C# Coleções — escolher e revisar

Fontes: "Selecting a Collection Class" e "Guidelines for Collections" (Framework Design Guidelines, texto de 2008: a própria doc avisa que parte pode estar desatualizada; trate como diretriz, não lei). Dúvida fora daqui → buscar na doc.

## Escolher a coleção (perguntas da doc)

| Necessidade | Opção |
|---|---|
| Sequência em que o item é descartado ao ler, FIFO | `Queue<T>` (`ConcurrentQueue<T>`, `ImmutableQueue<T>`) |
| LIFO | `Stack<T>` (`ConcurrentStack<T>`, `ImmutableStack<T>`) |
| Acesso por **índice** | `List<T>` (imutável: `ImmutableArray<T>`, `ImmutableList<T>`) |
| Acesso por **chave** | `Dictionary<TKey,TValue>` (ordenado: `SortedDictionary`, `SortedList`) |
| Um valor com chave embutida no item | `KeyedCollection<TKey,TItem>` |
| Ordenar diferente da inserção | `SortedDictionary` (mais rápido) ou `SortedList` (menos memória); `List<T>.Sort` com `IComparer<T>` |
| Busca/recuperação rápida | `Dictionary` é mais rápido que `SortedDictionary` na busca |
| Multi-thread | `ConcurrentDictionary`, `ConcurrentQueue`, `ConcurrentStack`, `ConcurrentBag` |
| Imutável | `Immutable*` / `IImmutableList<T>` etc. |
| Percorrer ambos os sentidos | `LinkedList<T>` |

- **Evite** os tipos não genéricos de `System.Collections` (`ArrayList`, `Hashtable`...). Use as versões genéricas/concorrentes (type safety).
- Strings: use `List<string>`, `Dictionary<string,string>` (não precisa de `StringCollection`).

## O que expor em API pública (guidelines)

| Local | Regra |
|---|---|
| Parâmetro | Use o tipo **menos especializado** possível, normalmente `IEnumerable<T>`. Evite `ICollection<T>` só para ler `Count` (teste dinamicamente se implementa). |
| Retorno/propriedade somente leitura | `ReadOnlyCollection<T>` (preferível), subclasse dela, ou `IEnumerable<T>` quando só iteração forward. |
| Retorno/propriedade leitura-escrita | `Collection<T>` ou subclasse. |
| Propriedade de coleção | **Não** tenha setter. Para trocar o conteúdo: `Clear` + `Add`/`AddRange`. |
| Vazio | **Nunca retorne `null`**: retorne coleção/array vazio. |
| `List<T>`, `Dictionary<,>`, `Hashtable`, `ArrayList` | **Não** em API pública: são estruturas de dados para implementação interna (usar `IDictionary<,>` etc.). |
| `IEnumerator<T>` | Só como retorno de `GetEnumerator`. |
| Array vs coleção | Prefira coleções; arrays em APIs de baixo nível/desempenho; `byte[]` em vez de coleção de bytes; não retorne cópia de array a cada getter. |
| Propriedade getter | Deve ser leve: não retorne *snapshot* (cópia O(n)); retorne coleção "viva". Coleções voláteis → snapshot ou `IEnumerable<T>`. |
| Tipos | Item tipado exato, não base; sem coleções fracamente tipadas. |

Nomes: sufixo `Collection` (lista de itens), `Dictionary` (IDictionary); sem sufixos que impliquem implementação (`LinkedList`, `Hashtable`); prefixo do item (`AddressCollection`); `ReadOnly` quando houver equivalente editável.

## Checklist de revisão
1. Retorno `List<T>`/`Dictionary` em método público de biblioteca → sugerir `ReadOnlyCollection<T>`/`IEnumerable<T>` (leitura) ou `Collection<T>` (leitura-escrita) e justificar (fonte: guidelines). `IReadOnlyList<T>` **não aparece** nesse texto de 2008; se sugerir, diga que é extensão moderna da diretriz (CONVENÇÃO).
2. Retorno `null` de coleção → coleção vazia.
3. Propriedade de coleção com `set` → remover setter.
4. Parâmetro `List<T>`/`ICollection<T>` sem necessidade → `IEnumerable<T>`.
5. Coleção não genérica → genérica.
6. Dictionary acessado por várias threads → `ConcurrentDictionary`.
7. Chave duplicada/ordem importa? Confirmar se a coleção escolhida atende.

Observação: em aplicações (não bibliotecas) o uso interno de `List<T>` é normal; a restrição é para a superfície pública reutilizável. Diga isso ao revisar app code e ajuste a severidade para Baixa.

## Fontes oficiais
- Selecting a collection class: https://learn.microsoft.com/en-us/dotnet/standard/collections/selecting-a-collection-class
- Guidelines for collections: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/guidelines-for-collections
- Thread-safe collections: https://learn.microsoft.com/en-us/dotnet/standard/collections/thread-safe/when-to-use-a-thread-safe-collection
