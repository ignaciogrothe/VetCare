#!/usr/bin/env bash
# Ejercita los endpoints contra la API levantada (docker compose up -d --build).
# Requisitos: bash, curl y python3. Se puede repetir: usa correos unicos.
#   bash pruebas/probar_api.sh                 # usa .env para las credenciales del admin
#   BASE=http://127.0.0.1:8080 bash pruebas/probar_api.sh
BASE="${BASE:-http://127.0.0.1:8080}"
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@clinica.cl}"
ID=$(date +%s)

req() {  # req METODO RUTA TOKEN [JSON] -> imprime y deja el cuerpo en $R
  local cab=(-H 'content-type: application/json')
  [ -n "$3" ] && cab+=(-H "authorization: Bearer $3")
  R=$(curl -s -w '\n%{http_code}' -X "$1" "$BASE$2" "${cab[@]}" ${4:+-d "$4"})
  CODIGO="${R##*$'\n'}"; R="${R%$'\n'*}"
  printf '%-34s -> %s\n' "$1 $2" "$CODIGO"
}
campo() { python3 -c "import sys,json; print(json.load(sys.stdin)$1)" <<<"$R"; }
esperar() { [ "$CODIGO" = "$1" ] || { echo "   ESPERABA $1 y llego $CODIGO: $R"; FALLO=1; }; }

req GET /api/salud "";                                   esperar 200
req POST /api/auth/login "" "{\"email\":\"$ADMIN_EMAIL\",\"clave\":\"$ADMIN_CLAVE\"}"; esperar 200
ADM=$(campo "['access_token']")
req POST /api/usuarios $ADM "{\"nombre\":\"Dra Vet\",\"email\":\"vet$ID@clinica.cl\",\"clave\":\"clave12345\",\"rol\":\"veterinario\"}"; esperar 201
VET_ID=$(campo "['id']")
req POST /api/usuarios $ADM "{\"nombre\":\"Rita Recepcion\",\"email\":\"rec$ID@clinica.cl\",\"clave\":\"clave12345\",\"rol\":\"recepcionista\"}"; esperar 201
req POST /api/auth/registro "" "{\"nombre\":\"Ana Duena\",\"email\":\"ana$ID@correo.cl\",\"clave\":\"clave12345\"}"; esperar 201
DUENO_ID=$(campo "['id']")
req POST /api/auth/registro "" "{\"nombre\":\"Ana Duena\",\"email\":\"ana$ID@correo.cl\",\"clave\":\"clave12345\"}"; esperar 409
req POST /api/auth/login "" "{\"email\":\"vet$ID@clinica.cl\",\"clave\":\"clave12345\"}"; VET=$(campo "['access_token']")
req POST /api/auth/login "" "{\"email\":\"rec$ID@clinica.cl\",\"clave\":\"clave12345\"}"; REC=$(campo "['access_token']")
req POST /api/auth/login "" "{\"email\":\"ana$ID@correo.cl\",\"clave\":\"clave12345\"}"; DUE=$(campo "['access_token']")

req POST /api/mascotas $REC '{"nombre":"X","especie":"dragon"}';  esperar 400
req POST /api/mascotas $REC "{\"nombre\":\"Firulais\",\"especie\":\"perro\",\"sexo\":\"macho\",\"peso_kg\":12.5,\"dueno_id\":$DUENO_ID}"; esperar 201
MID=$(campo "['id']")
req GET /api/mascotas/999999 $ADM;                         esperar 404
req GET "/api/mascotas?especie=perro" $DUE;                esperar 200
req PATCH /api/mascotas/$MID $REC '{"peso_kg":13}';        esperar 200

FECHA=$(python3 -c "import datetime as d; print((d.datetime.now()+d.timedelta(days=1)).replace(hour=10,minute=30,second=0,microsecond=0).strftime('%Y-%m-%dT%H:%M:%S'))")
CITA="{\"mascota_id\":$MID,\"veterinario_id\":$VET_ID,\"fecha_hora\":\"$FECHA\",\"motivo\":\"Control anual\"}"
req POST /api/citas $REC "$CITA";                          esperar 201
CID=$(campo "['id']")
req POST /api/citas $REC "$CITA";                          esperar 409   # mismo bloque
req GET /api/citas/$CID $DUE;                              esperar 200

req POST /api/citas/$CID/atencion $REC '{"diagnostico":"Otitis leve"}'; esperar 403
req POST /api/citas/$CID/atencion $VET '{"diagnostico":"Otitis leve","tratamiento":"Limpieza","medicamentos":[{"medicamento":"Otomax","dosis":"2 gotas","duracion_dias":7}]}'; esperar 201
req POST /api/citas/$CID/atencion $VET '{"diagnostico":"Otitis leve"}'; esperar 409
req GET /api/citas/$CID/atencion $DUE;                     esperar 200
req PATCH /api/citas/$CID/atencion $VET '{"tratamiento":"Limpieza diaria"}'; esperar 200

echo; echo "== Endpoint que combina MySQL y MongoDB =="
req GET /api/mascotas/$MID/historial $DUE;                 esperar 200
echo "$R" | python3 -m json.tool

req DELETE /api/mascotas/$MID $ADM;                        esperar 409   # tiene citas
echo; [ -z "$FALLO" ] && echo "Todas las pruebas pasaron." || { echo "HUBO FALLAS."; exit 1; }
