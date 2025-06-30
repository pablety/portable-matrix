# portable-matrix
### Crear Portable setup-matrix-usb.sh
Formatea tu USB (/dev/sda) como ext4.

Lo monta en /media/usb.

Instala Docker y el plugin Compose.

Crea la estructura y los servicios (Avahi mDNS, Postgres, Synapse, Element Web).

Genera la configuración de Synapse.

Arranca todo el stack.

Inicializa la BD y registra un usuario admin con la misma contraseña

Solo reemplaza (anda como esta) matrixpass por la contraseña que quieras usar para Postgres, Synapse y tu usuario admin.

chmod +x setup-matrix-usb.sh
./setup-matrix-usb.sh






# Al conectar el usb
### apply-usb-matrix.sh

He creado un script apply-usb-matrix.sh que, al ejecutarlo tras montar el USB en /media/usb,:

Verifica que el USB esté montado.

Ajusta permisos sobre toda la carpeta usb.

Extrae la IP con hostname -I | awk '{print $1}' y añade (si no existe ya) la línea IP miserver.local en /etc/hosts.

Baja y vuelve a levantar tu stack con docker compose down y docker compose up -d.

Para usarlo:

bash

sudo chmod +x /media/usb/apply-usb-matrix.sh
/media/usb/apply-usb-matrix.sh

Con eso tendrás tu /etc/hosts actualizado y tus contenedores corriendo en la nueva máquina automáticamente
