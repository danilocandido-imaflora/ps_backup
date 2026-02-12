
# Backup de Perfis de Usuário com PowerShell (Robocopy)

Script em PowerShell para realizar **backup seletivo de pastas de perfis de usuários Windows**, com **log detalhado**, **barra de progresso** e uso preferencial do **Robocopy** (com fallback para `Copy-Item` se o Robocopy não estiver disponível).

> **Objetivo:** Copiar, para um compartilhamento em rede, as pastas relevantes de cada perfil de usuário válido presente em `C:\Users`, excluindo perfis/sistema indesejados e algumas pastas específicas (ex.: OneDrive).

---

## Sumário

- [Visão Geral](#visão-geral)
- [Como o script funciona](#como-o-script-funciona)
- [Pré-requisitos](#pré-requisitos)
- [Uso](#uso)
- [Destino do backup (estrutura)](#destino-do-backup-estrutura)
- [Regras de seleção e exclusão](#regras-de-seleção-e-exclusão)
- [Robocopy: parâmetros e códigos de retorno](#robocopy-parâmetros-e-códigos-de-retorno)
- [Logs](#logs)
- [Personalização](#personalização)
- [Boas práticas e limitações](#boas-práticas-e-limitações)
- [Solução de problemas](#solução-de-problemas)
- [Licença](#licença)

---

## Visão Geral

- Enumera perfis de usuário via Registro (`HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList`).
- Filtra e **exclui** perfis de sistema/serviço e nomes indesejados.
- Para cada usuário elegível:
  - Lista pastas de primeiro nível no perfil (ex.: `Desktop`, `Documents`, etc.).
  - **Exclui** pastas como `OneDrive*`, `IMAFLORA*`, diretórios iniciados por `.` e itens com atributos **Oculto/Sistema**.
  - Copia o conteúdo para um caminho UNC de destino usando **Robocopy** (se existir) ou `Copy-Item` (fallback).
- Gera **log** por execução e exibe **progresso** por usuário e pasta.
- Interativo: solicita **ENTER** antes de iniciar a cópia.

---

## Como o script funciona

1. **Determina identificadores**  
   - `Nome do computador` → usado no caminho de destino.  
   - `Timestamp` → pasta única por execução (formato `yyyy-MM-dd_HH-mm`).

2. **Destino do backup**  
   - Cria (força) a pasta de destino informada e define o arquivo de log `backup.log`.

3. **Descoberta de perfis**  
   - Usa `ProfileList` para obter caminhos de perfil válidos.  
   - **Ignora** perfis de serviço/sistema e perfis que não residam em `\\Users\\`.  
   - Aplica a lista de exclusão por **nome** (configurável).

4. **Confirmação do usuário**  
   - Lista os usuários elegíveis e pede **ENTER** para iniciar.

5. **Cópia**  
   - Para cada pasta de primeiro nível do perfil (após filtros), cria a pasta correspondente no destino.  
   - Se `robocopy.exe` existir:
     - Executa com `/E /COPY:DAT /R:2 /W:3 /NFL /NDL /NP /TEE /LOG+`.
     - Registra **código de retorno** e significado simplificado no log.
   - Caso contrário, usa `Copy-Item -Recurse -Force`.

6. **Feedback**  
   - `Write-Progress` (barra de progresso) por usuário e por pasta.  
   - Tempo total e caminho do log ao final.

---

## Pré-requisitos

- **Windows** com **PowerShell 5.1+**.  
- Acesso de **leitura** aos perfis de usuário e **gravação** no compartilhamento de rede.  
- **Robocopy** (normalmente presente em `%SystemRoot%\System32\robocopy.exe`). Se ausente, o script usa `Copy-Item`.

> **Observação:** garanta que o usuário executando o script tenha permissão de **gravação** no destino UNC e **leitura** dos perfis.

---

## Uso

1. **Salvar o script** (ex.: `backup-usuarios.ps1`).

2. **Abrir** PowerShell (preferencialmente **como Administrador**, se necessário para permissão de leitura dos perfis).

3. **Executar**:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
   .\backup-usuarios.ps1
   ```

4. Confira a lista de usuários que terão backup e pressione **ENTER** para iniciar.

---

## Destino do backup (estrutura)

O destino é construído assim:

```
\\10.0.0.132\Backup\Backups\<NOME-DO-COMPUTADOR>\<AAAA-MM-DD_HH-MM>\
  ├─ <UsuarioA>\
  │   ├─ Documents\
  │   ├─ Desktop\
  │   └─ ...
  └─ <UsuarioB>\
      └─ ...
```

Você pode alterar a raiz do destino editando a variável:
```powershell
$BackupDestino = "\\10.0.0.132\Backup\Backups\$Equipamento\$(Get-Date -Format yyyy-MM-dd_HH-mm)"
```

---

## Regras de seleção e exclusão

- **Perfis ignorados por tipo**:
  - Caminhos contendo `\systemprofile\`, `\ServiceProfiles\`, `\LocalService`, `\NetworkService`.
  - Caminhos que **não** correspondam ao padrão `\\Users\\`.

- **Perfis ignorados por nome** (configurável em `$PerfisExcluirPorNome`):
  ```
  Default, Default User, Public, All Users, WDAGUtilityAccount,
  imaflora, defaultuser0, DWM-1
  ```

- **Pastas ignoradas dentro do perfil**:
  - Nomes que **comecem** com: `OneDrive*`, `IMAFLORA*`.
  - Nomes que **comecem com ponto** (`^\.`).
  - Pastas com atributo **Oculto** ou **Sistema**.

> **Observação:** A lista/padrões podem ser ajustados conforme sua necessidade (veja [Personalização](#personalização)).

---

## Robocopy: parâmetros e códigos de retorno

### Parâmetros utilizados

```text
/E           Copia subpastas, incluindo vazias
/COPY:DAT    Copia Dados, Atributos e Timestamps (não copia ACL/segurança)
/R:2         Até 2 tentativas por falha
/W:3         Espera 3 segundos entre tentativas
/NFL /NDL    Suprime listagens detalhadas de arquivos e diretórios
/NP          Sem exibição de progresso por arquivo
/TEE         Mostra saída no console e envia ao log
/LOG+:"..."  Anexa saída ao arquivo de log
```

> **Importante:** Como `/COPY:DAT` **não** inclui segurança (ACLs), as permissões NTFS **não** são preservadas no destino. Se você precisa preservar ACLs, veja sugestões em [Personalização](#personalização).

### Interpretação de códigos de retorno (simplificada no script)

| Código | Significado (resumo)                                  |
|------:|--------------------------------------------------------|
| 0     | Sem cópias; nada a fazer                               |
| 1     | Arquivos idênticos ou copiados com sucesso             |
| 2     | Alguns arquivos extras/removidos                       |
| 3     | Cópias e remoções bem-sucedidas                        |
| 5     | Alguns arquivos ignorados/novos                        |
| 6     | Novos arquivos e removidos                             |
| outro | Verifique detalhes no log                              |

> A tabela acima é um **resumo** utilizado pelo script. Para significados completos, consulte `robocopy /?` no Windows.

---

## Logs

- O arquivo de log fica em:  
  `\\...\\<NOME-DO-COMPUTADOR>\\<AAAA-MM-DD_HH-MM>\\backup.log`
- Para cada usuário:
  - Cabeçalho com timestamp de início.
  - Linhas com origem → destino e **código de retorno** do Robocopy (quando aplicável).
  - Duração do backup daquele usuário.
- Ao final:
  - Tempo total da execução.

---

## Personalização

### Caminho de destino
Edite a raiz e/ou o formato de data:
```powershell
$BackupDestino = "\\10.0.0.132\Backup\Backups\$Equipamento\$(Get-Date -Format yyyy-MM-dd_HH-mm)"
```

### Perfis a excluir por nome
Adicione/remova nomes conforme seu ambiente:
```powershell
$PerfisExcluirPorNome = @('Default','Default User','Public','All Users',
'WDAGUtilityAccount','imaflora','defaultuser0','DWM-1')
```

### Pastas a excluir dentro do perfil
O filtro atual ignora `OneDrive*`, `IMAFLORA*`, nomes iniciados com `.` e itens ocultos/sistema.  
Para incluir OneDrive, por exemplo, remova a condição correspondente:
```powershell
# Remover este predicado do Where-Object:
# ($_.Name -notlike "OneDrive*")
```

### Parâmetros do Robocopy
- Para **espelhar** (remover no destino o que não existe na origem), considere `/MIR` (cautela!).  
- Para **preservar ACLs**, substitua `/COPY:DAT` por `/COPY:DATSOU` (ou use `/COPYALL`).  
- Para **evitar seguir junctions**, você pode adicionar `/XJ` (dependendo da sua topologia).  
- Para **teste (sem copiar)**, adicione `/L` (lista o que faria).  
- Para **multithread**, adicione `/MT:n` (ex.: `/MT:16`).

> **Atenção:** `/MIR` pode **apagar dados** no destino. Use apenas se o destino deve refletir exatamente a origem.

### Execução não-interativa (agendada)
Remova ou comente a linha que aguarda ENTER:
```powershell
# [void][System.Console]::ReadLine()
```
E agende via **Agendador de Tarefas** usando uma conta de serviço com as permissões necessárias.

---

## Boas práticas e limitações

- **Arquivos abertos/bloqueados**: sem VSS (Shadow Copy), arquivos em uso podem não ser copiados. Ajuste `/R` e `/W` conforme necessidade, ou execute com apps fechados.  
- **Permissões**: o script **não** preserva ACLs por padrão (usa `/COPY:DAT`).  
- **Conectividade**: certifique-se de que o caminho UNC esteja acessível e com credenciais válidas (ex.: `net use \\10.0.0.132\Backup /user:DOMÍNIO\\usuário`).  
- **Espaço em disco**: verifique o espaço no compartilhamento de destino antes da execução.  
- **Desduplicação**: o script não faz dedup/várias versões; cada execução cria uma **nova pasta** com timestamp.  
- **Logs**: o log cresce com `/LOG+`. Faça rotação/limpeza conforme sua política.

---

## Solução de problemas

- **“Nenhum usuário elegível para backup.”**  
  Verifique se os perfis realmente estão em `C:\Users\...` e se não foram excluídos pela lista `$PerfisExcluirPorNome`.

- **Erro de acesso ao destino**  
  Verifique permissões no compartilhamento (`\\10.0.0.132\Backup\Backups\...`). Tente mapear previamente:
  ```powershell
  net use \\10.0.0.132\Backup /user:SEU_DOMINIO\SEU_USUARIO
  ```

- **Robocopy não encontrado**  
  O script usará `Copy-Item`. Caso queira o Robocopy, confirme se existe em `%SystemRoot%\System32\robocopy.exe`.

- **Performance baixa**  
  Ajuste `/R` e `/W`, adicione `/MT:n` (multithread, ex.: `/MT:16`) e considere executar quando houver menos atividade no disco/rede.

- **OneDrive não foi copiado**  
  Por padrão é **excluído**. Remova o filtro se desejar copiar.

---

## Licença

Defina a licença conforme sua necessidade (ex.: MIT, Apache-2.0).  
> _Este repositório ainda não especifica uma licença._

---

### Contexto e Escopo

- **Ambiente**: Windows com PowerShell 5.1+; destino em **compartilhamento UNC** acessível.  
- **Público**: administradores e técnicos que precisam realizar cópia de dados de perfis de usuário de forma controlada.

**Nível de confiança sobre a descrição acima:** **alto** (baseado na leitura direta do script fornecido, sem suposições além dos parâmetros explícitos).
