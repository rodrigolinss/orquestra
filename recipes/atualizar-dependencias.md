# Atualizar dependências provando que nada quebrou

## Para que serve

Para subir a versão de uma ou mais dependências (um pacote npm, uma gem,
uma lib Swift Package, uma versão de ferramenta como `tmux`/`jq` que o
`install.sh` verifica) quando você já decidiu que quer atualizar — não
para "ver se tem algo desatualizado", que é uma tarefa de levantamento,
não de mudança. Se você não sabe ainda o que está desatualizado, peça
primeiro um levantamento ("liste as dependências e as versões disponíveis,
não atualize nada"), e só depois use esta receita para a atualização em
si.

Não use esta receita para atualizar tudo de uma vez num projeto grande:
isso vira um pedido vago disfarçado de específico. Uma leva por vez —
mesmo que sejam várias dependências, elas devem estar todas relacionadas
(ex.: todas do mesmo ecossistema, ou todas patch/minor sem breaking
change conhecido).

## Texto da tarefa

```
Atualize [PREENCHER: nome da(s) dependência(s) e versão-alvo, ex: "tmux
para 3.4" ou "todas as deps do package.json em app/ para a última minor"]
em [PREENCHER: caminho do arquivo de manifesto, ex: install.sh, ou
app/Package.swift].

Antes de mudar qualquer coisa, verifique o changelog/notas de versão entre
a versão atual e a versão alvo e me diga nas notas se há alguma mudança
que quebra compatibilidade (breaking change) — se houver, pare e me avise
em vez de seguir.

Depois de atualizar, rode a suíte de testes do projeto
([PREENCHER: comando exato, ex: bin/guard-test.sh, ou o build do app em
app/build.sh]) e cole a saída completa nas notas. Se algo quebrar, não
tente consertar o código para se adaptar à nova versão — reverta a
atualização dessa dependência específica e registre nas notas por que ela
não pôde subir agora.

Não mude nenhuma outra dependência além da(s) listada(s) acima, mesmo que
o gerenciador de pacotes sugira outras atualizações no caminho.
```

## Modelo sugerido e por quê

**Sonnet.** Ler changelog, decidir se algo é breaking change e interpretar
saída de teste é raciocínio, não é braçal — mas também não exige a
profundidade de projeto que opus custaria. Use haiku só se a atualização
for de patch version trivial e o projeto tiver teste automatizado robusto
o bastante para você confiar no resultado sem revisão fina.

## Convém pedir plano antes?

Só se a atualização for de uma dependência com major version bump
(mudança que historicamente quebra API) ou se afetar múltiplos pontos do
projeto ao mesmo tempo (ex.: subir uma versão do Swift que afeta
`app/main.swift` inteiro). Nesse caso, peça plano para o agente mapear
antes todos os pontos de uso afetados. Para patch/minor sem breaking
change conhecido, pode ir direto — o critério de pronto já exige prova via
teste.

## Arquivos que o agente deve e não deve tocar

- **Pode editar:** o arquivo de manifesto de dependências indicado
  (`install.sh`, `app/Package.swift`, `package.json`/lockfile
  equivalente), e o arquivo de lock gerado automaticamente pela
  atualização.
- **Não deve tocar:** código de aplicação que consome a dependência,
  a menos que a própria atualização exija uma mudança de API — e nesse
  caso o agente deve parar e perguntar antes, não decidir sozinho.

## Critério de pronto

- O manifesto de dependências mostra a nova versão.
- As notas trazem a saída da suíte de testes/build rodando depois da
  atualização, com resultado de sucesso — não a afirmação de que "deve
  funcionar".
- Se havia risco de breaking change, as notas dizem explicitamente que
  foi verificado e por quê foi considerado seguro (ou por que foi
  revertido).
- Nenhuma dependência fora da lista pedida mudou de versão.
