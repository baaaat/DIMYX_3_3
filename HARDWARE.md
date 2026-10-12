# Câblage ESP32-C3 et ruban LED

Cette fiche concerne un ruban RGB analogique 5 V à anode commune (`+5V / R / G / B`), pas un ruban adressable WS2812/NeoPixel.

```text
Alimentation 5 V (+) ─────────────── +5V du ruban
Alimentation GND ─────┬───────────── GND ESP32-C3
                       └─ Source Q1/Q2/Q3
R du ruban ─────────────── Drain Q1       Gate Q1 ← GPIO4 via 220 Ω
G du ruban ─────────────── Drain Q2       Gate Q2 ← GPIO5 via 220 Ω
B du ruban ─────────────── Drain Q3       Gate Q3 ← GPIO6 via 220 Ω
                                        Chaque Gate → GND via 10 kΩ
```

Le FQP30N06L vu de face, inscription lisible et pattes vers le bas, est normalement `1 Gate`, `2 Drain`, `3 Source`; sa languette est reliée au Drain. Vérifier le marquage du composant reçu avant mise sous tension. Les masses alimentation, ESP32 et sources MOSFET doivent être communes.

Prévoir une alimentation 5 V dimensionnée sur le courant réel du ruban, un fusible, et un condensateur de 470 à 1000 µF près du ruban. L'ESP32 ne doit jamais alimenter directement le ruban.

Attention : la fiche du FQP30N06L spécifie le `RDS(on)` à `VGS = 5 V` et `10 V`, pas à 3,3 V. Le pilotage direct par ESP32-C3 doit donc être testé en température et en courant. Pour un ruban puissant, préférer un MOSFET dont le `RDS(on)` est garanti à 2,5/3,3 V ou ajouter un driver de grille.

Le firmware `firmware/esp32-c3/dimyx_esp32_c3.ino` configure une carte maître en point d'accès `DIMYX-ESP32-C3`, à l'adresse `192.168.4.1`, port UDP `4210`. Les cartes supplémentaires sont configurées en stations avec des adresses fixes différentes (`192.168.4.11`, `.12`, etc.). Le PC ne se connecte qu'au réseau du maître ; aucun routeur ni accès Internet n'est requis. Ajouter ensuite chaque carte réellement programmée dans `esp32Boards.json`, sans recopier une configuration de démonstration non vérifiée.
