#!/bin/bash

# Função para tratar falhas e parar o script em caso de erro
function checar_erro {
    if [ $? -ne 0 ]; then
        echo "Erro: $1"
        exit 1
    fi
}

# Detectar o sistema operacional e definir o diretório base e o URL de download do binário correto
OS_TYPE=$(uname)
XDB_BIN_URL=""
INSTALL_DIR=""

if [[ "$OS_TYPE" == "Linux" ]]; then
    INSTALL_DIR="/etc/xdbsecure"
    XDB_BIN_URL="https://github.com/XDIGITALBRASIL/XDBSecure-Sis/raw/main/Linux/XDBSecure"
elif [[ "$OS_TYPE" == "Darwin" ]]; then
    INSTALL_DIR="/etc/xdbsecure"
    XDB_BIN_URL="https://github.com/XDIGITALBRASIL/XDBSecure-Sis/raw/main/Mac/XDBSecure"
elif [[ "$OS_TYPE" == "MINGW64_NT" ]]; then
    INSTALL_DIR="C:\\XDBSecure"
    XDB_BIN_URL="https://github.com/XDIGITALBRASIL/XDBSecure-Sis/raw/main/Windows/XDBSecure.exe"
else
    echo "Sistema operacional não suportado: $OS_TYPE"
    exit 1
fi

# Criar o diretório de instalação se não existir
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "Criando diretório de instalação: $INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
    checar_erro "Falha ao criar o diretório de instalação."
fi

# Perguntar as configurações do cliente
read -p "Digite o subdomínio (ex: sub.cliente.com): " SUBDOMINIO
read -p "Digite a porta para a API rodar (ex: 3000): " PORTA
read -p "Digite a senha para o token de autenticação: " SENHA_TOKEN
read -p "Digite a senha para criptografia dos dados: " SENHA_CRIPTO

echo "Subdomínio configurado: $SUBDOMINIO"

# Verificar e instalar Nginx ou Apache se necessário
if command -v nginx &> /dev/null; then
    echo "Nginx detectado no servidor."
    SERVIDOR_WEB="nginx"
elif command -v apache2 &> /dev/null; then
    echo "Apache detectado no servidor."
    SERVIDOR_WEB="apache"
else
    echo "Nenhum servidor web detectado. Instalando Nginx..."
    sudo apt-get update
    checar_erro "Falha ao atualizar o sistema."

    sudo apt-get install nginx -y
    checar_erro "Falha ao instalar o Nginx."
    SERVIDOR_WEB="nginx"
fi

# Baixar o binário do XDBSecure apropriado para o sistema no diretório de instalação
echo "Baixando o XDBSecure no diretório $INSTALL_DIR..."
sudo curl -L -o "$INSTALL_DIR/XDBSecure" "$XDB_BIN_URL"
checar_erro "Falha ao baixar o binário XDBSecure."

# Dar permissão de execução ao binário
sudo chmod +x "$INSTALL_DIR/XDBSecure"
checar_erro "Falha ao configurar as permissões do binário XDBSecure."

# Criar arquivo de configuração para o XDBSecure
echo "Criando arquivo de configuração..."
sudo bash -c "cat > $INSTALL_DIR/config.json <<EOF
{
    \"subdominio\": \"$SUBDOMINIO\",
    \"porta\": $PORTA,
    \"senhaToken\": \"$SENHA_TOKEN\",
    \"senhaCripto\": \"$SENHA_CRIPTO\"
}
EOF"
checar_erro "Falha ao criar o arquivo de configuração."

# Definir permissões corretas para o diretório de chaves e certificados
sudo mkdir -p /etc/nginx/ssl
checar_erro "Falha ao criar o diretório para certificados."

sudo chmod 700 /etc/nginx/ssl
checar_erro "Falha ao configurar permissões no diretório de certificados."

# Configurar o servidor web com o subdomínio e proxy
if [ "$SERVIDOR_WEB" == "nginx" ]; then
    echo "Configurando Nginx para o subdomínio $SUBDOMINIO"

    # Exemplo de configuração baseado no seu modelo
    backend_hostname=$(echo "${SUBDOMINIO}")
    
    # Verificar se o certificado SSL existe antes de configurar o Nginx com SSL
    if [[ -f "/etc/nginx/ssl/$SUBDOMINIO.crt" && -f "/etc/nginx/ssl/$SUBDOMINIO.key" ]]; then
        echo "Certificados SSL encontrados. Configurando Nginx com SSL..."
        sudo bash -c "cat > /etc/nginx/sites-available/$SUBDOMINIO << 'END'
server {
  listen 443 ssl;
  server_name $backend_hostname;

  ssl_certificate /etc/nginx/ssl/$SUBDOMINIO.crt;
  ssl_certificate_key /etc/nginx/ssl/$SUBDOMINIO.key;

  location / {
    proxy_pass http://127.0.0.1:$PORTA;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
END"
        checar_erro "Falha ao configurar o Nginx com SSL."
    else
        echo "Certificados SSL não encontrados, configurando Nginx sem SSL temporariamente..."
        sudo bash -c "cat > /etc/nginx/sites-available/$SUBDOMINIO << 'END'
server {
  listen 80;
  server_name $backend_hostname;

  location / {
    proxy_pass http://127.0.0.1:$PORTA;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
END"
        checar_erro "Falha ao configurar o Nginx sem SSL."
    fi

    # Criar link simbólico, forçando recriação se já existir
    sudo ln -sf /etc/nginx/sites-available/$SUBDOMINIO /etc/nginx/sites-enabled/
    checar_erro "Falha ao criar link simbólico no Nginx."

    sudo nginx -t
    checar_erro "A configuração do Nginx falhou."

    sudo systemctl restart nginx
    checar_erro "Falha ao reiniciar o Nginx."

elif [ "$SERVIDOR_WEB" == "apache" ]; then
    echo "Configurando Apache para o subdomínio $SUBDOMINIO"
    sudo bash -c "cat > /etc/apache2/sites-available/$SUBDOMINIO.conf <<EOF
<VirtualHost *:443>
    ServerName $SUBDOMINIO

    SSLEngine on
    SSLCertificateFile /etc/nginx/ssl/$SUBDOMINIO.crt
    SSLCertificateKeyFile /etc/nginx/ssl/$SUBDOMINIO.key

    ProxyPass / http://127.0.0.1:$PORTA/
    ProxyPassReverse / http://127.0.0.1:$PORTA/
</VirtualHost>
EOF"
    checar_erro "Falha ao configurar o Apache."

    sudo a2ensite $SUBDOMINIO
    checar_erro "Falha ao habilitar o site no Apache."

    sudo systemctl restart apache2
    checar_erro "Falha ao reiniciar o Apache."
fi

# Verificar se o PM2 está instalado
if ! command -v pm2 &> /dev/null; then
    echo "PM2 não encontrado. Instalando PM2..."
    sudo npm install -g pm2
    checar_erro "Falha ao instalar o PM2."
fi

# Iniciar o XDBSecure com o PM2 e configurá-lo para iniciar automaticamente
echo "Iniciando o XDBSecure com o PM2..."
pm2 start "$INSTALL_DIR/XDBSecure" --name XDBSecure --interpreter none --watch
checar_erro "Falha ao iniciar o XDBSecure no PM2."

# Configurar o PM2 para iniciar automaticamente no boot do sistema
pm2 startup
checar_erro "Falha ao configurar o PM2 para iniciar automaticamente."

pm2 save
checar_erro "Falha ao salvar o estado do PM2."

echo "Instalação do XDBSecure concluída! O serviço está rodando e gerenciado pelo PM2."
