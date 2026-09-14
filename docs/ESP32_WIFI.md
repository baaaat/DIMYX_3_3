# ESP32 WiFi

DIMYX peut charger plusieurs cibles ESP32 depuis `esp32Boards.json`.

Exemple :

```json
{
  "boards": [
    {"id":"ESP1","host":"192.168.1.201","port":4210,"enabled":true},
    {"id":"ESP2","host":"192.168.1.202","port":4210,"enabled":true}
  ]
}
```

Le transport utilise UDP. Le contrat reprend les commandes texte du lien serie :

- `H\n` : heartbeat
- `P,<pin>,<valeur>\n` : sortie 0..4095
- `X\n` : blackout

Ce patch prepare le registre et le transport multi-cartes mais ne route encore aucune tranche vers le WiFi. Tant que le patch d'adressage par tranche n'est pas applique, les sorties physiques restent USB.