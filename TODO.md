# Suivi

- [x] Différer le layout du menu FX au relâchement de la souris pour éviter les interactions ControlP5 avec SEQ + FX.
- [x] Terminer les traitements `effect_` et `fxChoice_` par un `return` dans `controlEvent`.

- [x] Remplacer les interrupteurs RGB/SEQ par des capsules avec curseur rond et états OFF/ON explicites.
- [x] Ajouter le clonage des réglages et des pas d’une tranche vers une autre.
- [x] Harmoniser les boutons, menus, champs et curseurs avec les capsules RGB/SEQ.
- [x] Adapter la fenêtre aux petits écrans avec pagination des tranches, vues scènes/sorties/USB et blackout permanent.
- [x] Ajouter des tests de compilation, de disposition et d’interactions sur cinq résolutions.
- [ ] Valider manuellement l’interface, les scènes et les sorties matérielles selon CONTRIBUTING.md.
- [x] Supprimer le chip rgb on/off sur la vue console, il est visible uniquement en vue SORTIES
- [x] Retablir le mode "blind" : programmation sans agir sur les sorties
- [ ] Le sequenceur agit aussi sur le mode mono; Actuellement, l'animation UI est ok mais rien en sortie
- [ ] retabllir un menu deroulant fonctionnel pour les fx
- [x] Renommer "Sortie/USB" en "Sorties"
- [ ] Préparer le support multi-carte wifi ESP32. 
- [ ] En plus des pins, il faut pouvoir adresser une carte à une tranche
