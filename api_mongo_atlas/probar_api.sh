#!/usr/bin/env bash
# Pruebas contra el servidor corriendo (python run.py, o docker compose up).
#   bash probar_api.sh                      # por defecto http://127.0.0.1:5001
#   BASE=http://127.0.0.1:5000 bash probar_api.sh
B="${BASE:-http://127.0.0.1:5001}"
ok=0; fallo=0
CITA=$(( $(date +%s) % 1000000000 ))   # cita_id nuevo en cada corrida

probar() {   # probar "titulo" esperado METODO ruta [cuerpo]
  local titulo="$1" esperado="$2" metodo="$3" ruta="$4" cuerpo="$5"
  local codigo args=(-s -o /tmp/_resp.json -w "%{http_code}" -X "$metodo" "$B$ruta")
  [ -n "$cuerpo" ] && args+=(-H "Content-Type: application/json" -d "$cuerpo")
  codigo=$(curl "${args[@]}")
  if [ "$codigo" = "$esperado" ]; then
    printf "  OK    %-3s %s\n" "$codigo" "$titulo"; ok=$((ok+1))
  else
    printf "  FALLA %-3s %s  (se esperaba %s)\n" "$codigo" "$titulo" "$esperado"; fallo=$((fallo+1))
  fi
}

echo; echo "== Salud =="
probar "la API y la base responden" 200 GET "/api/salud"

echo; echo "== Crear =="
CUERPO="{\"cita_id\":$CITA,\"diagnostico\":\"Otitis externa leve\",\"tratamiento\":\"Limpieza diaria\",\"medicamentos\":[{\"medicamento\":\"Otomax\",\"dosis\":\"2 gotas\",\"duracion_dias\":7}]}"
probar "crear atencion" 201 POST "/api/atenciones" "$CUERPO"
ID=$(python3 -c "import json;print(json.load(open('/tmp/_resp.json'))['id'])")
echo "        -> _id que genero MongoDB: $ID"
probar "misma cita otra vez (indice unico)" 409 POST "/api/atenciones" "$CUERPO"

echo; echo "== Validacion =="
probar "sin cita_id"          400 POST "/api/atenciones" '{"diagnostico":"Algo largo"}'
probar "diagnostico corto"    400 POST "/api/atenciones" '{"cita_id":1,"diagnostico":"no"}'
probar "medicamento invalido" 400 POST "/api/atenciones" '{"cita_id":1,"diagnostico":"Algo largo","medicamentos":[{"medicamento":"A"}]}'

echo; echo "== Leer =="
probar "obtener por id"        200 GET "/api/atenciones/$ID"
probar "id con formato malo"   400 GET "/api/atenciones/abc"
probar "id inexistente"        404 GET "/api/atenciones/64b7f0000000000000000000"
probar "listar"                200 GET "/api/atenciones"
probar "filtrar por medicamento" 200 GET "/api/atenciones?medicamento=otomax"
probar "orden invalido"        400 GET "/api/atenciones?orden=diagnostico"
probar "resumen de medicamentos" 200 GET "/api/atenciones/resumen/medicamentos"

echo; echo "== Actualizar y eliminar =="
probar "PUT cambia el tratamiento" 200 PUT "/api/atenciones/$ID" '{"tratamiento":"Limpieza cada 48 h"}'
probar "PUT no cambia cita_id"     400 PUT "/api/atenciones/$ID" '{"cita_id":5}'
probar "eliminar"                  204 DELETE "/api/atenciones/$ID"
probar "eliminar otra vez"         404 DELETE "/api/atenciones/$ID"

echo; echo "  $ok OK, $fallo con fallas"
[ "$fallo" = 0 ]
