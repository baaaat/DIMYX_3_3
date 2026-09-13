# BOM — Contrôleur DIMYX ESP32-C3 + ruban RGB 5 V

## 1. Objet

Ce document décrit la partie matérielle du contrôleur DIMYX chargé de piloter un ruban LED RGB analogique à partir d'un ESP32-C3.

Configuration retenue :

- contrôleur : ESP32-C3 ;
- alimentation : powerbank USB 5 V ;
- ruban : RGB analogique 5 V ;
- longueur : 5 m ;
- puissance actuellement retenue : environ 6 W ;
- courant maximal actuellement retenu : environ 1,2 A ;
- câblage du ruban : `+5V / R / G / B` ;
- architecture : anode commune +5 V ;
- commande des trois couleurs par MOSFET N en low-side ;
- modulation PWM depuis l'ESP32-C3.

> IMPORTANT : si l'étiquette ou la fiche technique du ruban indique un courant supérieur à 1,2 A, l'alimentation, le fusible et les sections de câble devront être redimensionnés.

---

# 2. BOM

| Repère | Qté | Composant | Référence retenue | Caractéristiques / remarque |
|---|---:|---|---|---|
| U1 | 1 | Carte ESP32-C3 | ESP32-C3, carte de développement avec alimentation USB/5 V | Le modèle exact de la carte utilisée devra être ajouté dès qu'il est définitivement choisi |
| Q1 | 1 | MOSFET canal N | **AO3400A — Alpha & Omega Semiconductor** | Canal rouge |
| Q2 | 1 | MOSFET canal N | **AO3400A — Alpha & Omega Semiconductor** | Canal vert |
| Q3 | 1 | MOSFET canal N | **AO3400A — Alpha & Omega Semiconductor** | Canal bleu |
| R1 | 1 | Résistance de grille | **220 Ω, 1/4 W** | GPIO R → Gate Q1 |
| R2 | 1 | Résistance de grille | **220 Ω, 1/4 W** | GPIO G → Gate Q2 |
| R3 | 1 | Résistance de grille | **220 Ω, 1/4 W** | GPIO B → Gate Q3 |
| R4 | 1 | Pull-down Gate | **10 kΩ, 1/4 W** | Gate Q1 → GND |
| R5 | 1 | Pull-down Gate | **10 kΩ, 1/4 W** | Gate Q2 → GND |
| R6 | 1 | Pull-down Gate | **10 kΩ, 1/4 W** | Gate Q3 → GND |
| C1 | 1 | Condensateur électrolytique | **1000 µF / 10 V minimum** | Sur le bus 5 V près du départ du ruban |
| C2 | 1 | Condensateur céramique | **100 nF / 50 V X7R** | Découplage du circuit de puissance |
| C3 | 1 | Condensateur | **10 µF / 10 V minimum** | Découplage local du 5 V, recommandé |
| F1 | 1 | Fusible | **2 A temporisé** | Protection de la branche alimentant le ruban |
| J1 | 1 | Connecteur alimentation | USB / breakout 5 V ≥ 3 A | Entrée depuis powerbank |
| J2 | 1 | Bornier | 4 voies, pas 5,08 mm, ≥ 3 A | Sortie `+5V / R / G / B` vers ruban |
| — | 1 | Powerbank | **5 V / 3 A recommandé** | 2 A peut suffire mais laisse moins de marge |
| — | 1 | Câble USB | **3 A minimum** | Câble court recommandé |
| — | 1 | Ruban RGB | **5 V, 5 m, +5V/R/G/B** | Ruban analogique, pas adressable |
| — | 3 | Adaptateur SOT-23 → 2,54 mm | Pour AO3400A | Seulement pour prototype sur plaque |
| — | 1 | PCB / plaque prototype | — | Pour le montage de l'étage de puissance |

---

# 3. MOSFET retenu

## AO3400A

Référence principale :

**AO3400A — Alpha & Omega Semiconductor**

Type :

- MOSFET canal N ;
- boîtier SOT-23 ;
- VDS max : 30 V ;
- courant largement supérieur aux besoins du ruban ;
- faible charge de grille ;
- adapté à la commutation PWM.

Caractéristique importante :

```text
RDS(on) ≤ 48 mΩ avec VGS = 2,5 V
