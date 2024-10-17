#!/bin/bash

# Obter o diretório onde o script está sendo executado
SCRIPT_DIR=$(pwd)

# Detectar o sistema operacional e definir o URL de download do binário correto
OS_TYPE=$(uname)
XDB_BIN_URL=""

if [[ "$OS_TYPE" == "Linux" ]]; then
    XDB_BIN_URL="https://github.com/XDIGITALBRASIL/XDBSecure-Sis/raw/main/Linux/XDBSecure"
elif [[ "$OS_TYPE" == "Darwin" ]]; then
    XDB_BIN_URL="https://github.com/XDIGITALBRASIL/XDBSecure-Sis/raw/main/Mac/XDBSecure"
elif [[ "$OS_TYPE" == "MINGW64_NT" ]]; then
    XDB_BIN_URL="https://github.com/XDIGITALBRASIL/XDBSecure-Sis/raw/main/Windows/XDBSecure.exe"
else
    echo "Sistema operacional não suportado: $OS_TYPE"
    exit 1
fi

# Perguntar as configurações do cliente
read -p "Digite o subdomínio (ex: sub.cliente.com): " SUBDOMINIO
read -p "Digite a porta para a API rodar (ex: 3000): " PORTA
read -p "Digite a senha para o token de autenticação: " SENHA_TOKEN
read -p "Digite a senha para criptografia dos dados: " SENHA_CRIPTO

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
    sudo apt-get install nginx -y
    SERVIDOR_WEB="nginx"
fi

# Baixar o binário do XDBSecure apropriado para o sistema na mesma pasta do script
echo "Baixando o XDBSecure no diretório $SCRIPT_DIR..."
sudo curl -L -o "$SCRIPT_DIR/XDBSecure" "$XDB_BIN_URL"
sudo chmod +x "$SCRIPT_DIR/XDBSecure"

# Criar arquivo de configuração para o XDBSecure
echo "Criando arquivo de configuração..."
sudo mkdir -p /etc/xdbsecure
sudo bash -c "cat > /etc/xdbsecure/config.json <<EOF
{
    \"subdominio\": \"$SUBDOMINIO\",
    \"porta\": $PORTA,
    \"senhaToken\": \"$SENHA_TOKEN\",
    \"senhaCripto\": \"$SENHA_CRIPTO\"
}
EOF"

# Definir permissões corretas para o diretório de chaves e certificados
sudo mkdir -p /etc/nginx/ssl
sudo chmod 700 /etc/nginx/ssl

# Configurar o servidor web com o subdomínio e proxy
if [ "$SERVIDOR_WEB" == "nginx" ]; then
    echo "Configurando Nginx para o subdomínio $SUBDOMINIO"
    sudo bash -c "cat > /etc/nginx/sites-available/$SUBDOMINIO <<EOF
server {
    listen 443 ssl;
    server_name $SUBDOMINIO;

    ssl_certificate /etc/nginx/ssl/$SUBDOMINIO.crt;
    ssl_certificate_key /etc/nginx/ssl/$SUBDOMINIO.key;

    location / {
        proxy_pass http://localhost:$PORTA;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF"
    sudo ln -s /etc/nginx/sites-available/$SUBDOMINIO /etc/nginx/sites-enabled/
    sudo service nginx restart

elif [ "$SERVIDOR_WEB" == "apache" ]; then
    echo "Configurando Apache para o subdomínio $SUBDOMINIO"
    sudo bash -c "cat > /etc/apache2/sites-available/$SUBDOMINIO.conf <<EOF
<VirtualHost *:443>
    ServerName $SUBDOMINIO

    SSLEngine on
    SSLCertificateFile /etc/nginx/ssl/$SUBDOMINIO.crt
    SSLCertificateKeyFile /etc/nginx/ssl/$SUBDOMINIO.key

    ProxyPass / http://localhost:$PORTA/
    ProxyPassReverse / http://localhost:$PORTA/
</VirtualHost>
EOF"
    sudo a2ensite $SUBDOMINIO
    sudo service apache2 restart
fi

# Verificar se o PM2 está instalado
if ! command -v pm2 &> /dev/null; then
    echo "PM2 não encontrado. Instalando PM2..."
    sudo npm install -g pm2
fi

# Iniciar o XDBSecure com o PM2 e configurá-lo para iniciar automaticamente
echo "Iniciando o XDBSecure com o PM2..."
pm2 start "$SCRIPT_DIR/XDBSecure" --name XDBSecure --watch

# Configurar o PM2 para iniciar automaticamente no boot do sistema
pm2 startup
pm2 save

echo "Instalação do XDBSecure concluída! O serviço está rodando e gerenciado pelo PM2."
echo "Aguarde o envio do certificado e da chave privada via API."
