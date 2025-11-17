program GitBranchManager;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils, System.Classes, System.JSON, Winapi.Windows, Vcl.Dialogs;

function ExecuteCommand(const Command, WorkingDir: string): Boolean;
var
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
begin
  Result := False;
  FillChar(StartupInfo, SizeOf(TStartupInfo), 0);
  StartupInfo.cb := SizeOf(TStartupInfo);
  StartupInfo.dwFlags := STARTF_USESHOWWINDOW;
  StartupInfo.wShowWindow := SW_SHOW;

  if CreateProcess(nil, PChar('cmd.exe /C ' + Command), nil, nil, False,
    CREATE_NEW_CONSOLE or NORMAL_PRIORITY_CLASS, nil, PChar(WorkingDir),
    StartupInfo, ProcessInfo) then
  begin
    WaitForSingleObject(ProcessInfo.hProcess, INFINITE);
    CloseHandle(ProcessInfo.hProcess);
    CloseHandle(ProcessInfo.hThread);
    Result := True;
  end;
end;

procedure MostrarMenuRepositorios(JSONObject: TJSONObject);
var
  RepositoriosArray: TJSONArray;
  I: Integer;
begin
  Writeln('');
  Writeln('=== REPOSITÓRIOS DISPONÍVEIS ===');
  RepositoriosArray := JSONObject.GetValue('repositorios') as TJSONArray;
  for I := 0 to RepositoriosArray.Count - 1 do
  begin
    Writeln(Format('%d. %s', [I + 1,
      (RepositoriosArray.Items[I] as TJSONObject).GetValue('nome').Value]));
  end;
end;

procedure MostrarMenuSistemas(JSONObject: TJSONObject);
var
  SistemasArray: TJSONArray;
  I: Integer;
  SistemaObj: TJSONObject;
begin
  Writeln('');
  Writeln('=== SISTEMAS DISPONÍVEIS ===');
  SistemasArray := JSONObject.GetValue('sistemas') as TJSONArray;
  for I := 0 to SistemasArray.Count - 1 do
  begin
    SistemaObj := SistemasArray.Items[I] as TJSONObject;
    Writeln(Format('%d. %s -> %s', [I + 1,
      SistemaObj.GetValue('sigla').Value,
      SistemaObj.GetValue('pasta').Value]));
  end;
end;

function SelecionarOpcao(MaxOpcoes: Integer): Integer;
var
  Opcao: string;
begin
  Write('Selecione uma opção (número): ');
  Readln(Opcao);

  if TryStrToInt(Opcao, Result) then
  begin
    if (Result < 1) or (Result > MaxOpcoes) then
    begin
      Writeln('Opção inválida!');
      Result := -1;
    end;
  end
  else
  begin
    Writeln('Digite um número válido!');
    Result := -1;
  end;
end;

var
  ConfigFile: TStringList;
  JSONObject: TJSONObject;
  RepositoriosArray, SistemasArray: TJSONArray;
  Opcao: Integer;
  RepositorioURL, RepositorioNome, SistemaSigla, SistemaPasta: string;
  BranchNumber, BranchName, NomePasta, ComandoGit, Resposta: string;
  PastaDestino: string;
  SistemaObj: TJSONObject;

begin
  try
    Writeln('=== GIT BRANCH MANAGER ===');

    // Verifica se recebeu parâmetro do diretório
    if ParamCount > 0 then
    begin
      PastaDestino := ParamStr(1);
      Writeln('Diretório selecionado: ', PastaDestino);
    end
    else
    begin
      // Se não recebeu parâmetro, usa o diretório atual
      PastaDestino := GetCurrentDir;
      Writeln('Usando diretório atual: ', PastaDestino);
    end;

    // Verifica se o diretório existe
    if not DirectoryExists(PastaDestino) then
    begin
      Writeln('Erro: Diretório não existe: ', PastaDestino);
      Writeln('Pressione Enter para sair...');
      Readln;
      Exit;
    end;

    // Carrega configuração
    if not FileExists('config.json') then
    begin
      Writeln('Erro: Arquivo config.json não encontrado!');
      Writeln('Certifique-se que config.json está na mesma pasta do executável.');
      Writeln('Pressione Enter para sair...');
      Readln;
      Exit;
    end;

    ConfigFile := TStringList.Create;
    ConfigFile.LoadFromFile('config.json');

    JSONObject := TJSONObject.ParseJSONValue(ConfigFile.Text) as TJSONObject;
    RepositoriosArray := JSONObject.GetValue('repositorios') as TJSONArray;
    SistemasArray := JSONObject.GetValue('sistemas') as TJSONArray;

    // Seleção do repositório
    repeat
      MostrarMenuRepositorios(JSONObject);
      Opcao := SelecionarOpcao(RepositoriosArray.Count);
    until Opcao <> -1;

    RepositorioURL := (RepositoriosArray.Items[Opcao - 1] as TJSONObject).GetValue('url').Value;
    RepositorioNome := (RepositoriosArray.Items[Opcao - 1] as TJSONObject).GetValue('nome').Value;

    // Seleção do sistema
    repeat
      MostrarMenuSistemas(JSONObject);
      Opcao := SelecionarOpcao(SistemasArray.Count);
    until Opcao <> -1;

    SistemaObj := SistemasArray.Items[Opcao - 1] as TJSONObject;
    SistemaSigla := SistemaObj.GetValue('sigla').Value;
    SistemaPasta := SistemaObj.GetValue('pasta').Value;

    // Número da branch
    Write('Digite o número da branch (ex: 35828): ');
    Readln(BranchNumber);

    // Nome descritivo da branch
    Write('Digite o nome descritivo da branch: ');
    Readln(BranchName);

    // Monta nome da pasta
    NomePasta := Format('%s %s %s', [BranchNumber, SistemaSigla, BranchName]);
    Writeln(Format('Nome da pasta: "%s"', [NomePasta]));

    // Confirmação
    Writeln('');
    Writeln('=== RESUMO DA OPERAÇÃO ===');
    Writeln(Format('Repositório: %s', [RepositorioNome]));
    Writeln(Format('Sistema: %s', [SistemaSigla]));
    Writeln(Format('Pasta do Sistema: %s', [SistemaPasta]));
    Writeln(Format('Branch: feature/%s', [BranchNumber]));
    Writeln(Format('Pasta do Clone: %s', [NomePasta]));
    Writeln(Format('Diretório Destino: %s', [PastaDestino]));
    Writeln('');

    Write('Confirmar e executar? (S/N): ');
    Readln(Resposta);

    if (Resposta = 'S') or (Resposta = 's') then
    begin
      Writeln('');
      Writeln('Executando clone...');

      // Monta comando Git - agora usando PastaDestino
      ComandoGit := Format('git clone -b feature/%s --single-branch %s "%s\%s"',
        [BranchNumber, RepositorioURL, PastaDestino, NomePasta]);

      Writeln('Comando: ', ComandoGit);
      Writeln('Aguarde...');

      // Executa clone no diretório selecionado
      if ExecuteCommand(ComandoGit, PastaDestino) then
      begin
        Writeln('Clone realizado com sucesso!');

        // Verifica se a pasta foi criada
        if DirectoryExists(IncludeTrailingPathDelimiter(PastaDestino) + NomePasta) then
        begin
          Writeln('Pasta criada: ', NomePasta);

          // Executa boss install na pasta do sistema
          Writeln('Executando boss install na pasta do sistema...');
          if DirectoryExists(SistemaPasta) then
          begin
            if ExecuteCommand('boss install', SistemaPasta) then
            begin
              Writeln('boss install executado com sucesso em: ', SistemaPasta);
            end
            else
            begin
              Writeln('Erro ao executar boss install.');
            end;
          end
          else
          begin
            Writeln('Aviso: Pasta do sistema não encontrada: ', SistemaPasta);
            Writeln('Pulando boss install.');
          end;
        end
        else
        begin
          Writeln('Aviso: Pasta do clone não foi criada.');
        end;
      end
      else
      begin
        Writeln('Erro ao executar git clone.');
      end;
    end
    else
    begin
      Writeln('Operação cancelada.');
    end;

    JSONObject.Free;
    ConfigFile.Free;

    Writeln('');
    Writeln('Pressione Enter para sair...');
    Readln;

  except
    on E: Exception do
    begin
      Writeln('Erro: ', E.Message);
      Writeln('Pressione Enter para sair...');
      Readln;
    end;
  end;
end.
