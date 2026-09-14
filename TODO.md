# Suivi

- [x] Différer le layout du menu FX au relâchement de la souris pour éviter les interactions ControlP5 avec SEQ + FX.
- [x] Terminer les traitements `effect_` et `fxChoice_` par un `return` dans `controlEvent`.

- [x] Remplacer les interrupteurs RGB/SEQ par des capsules avec curseur rond et états OFF/ON explicites.
- [x] Ajouter le clonage des réglages et des pas d’une tranche vers une autre.
- [x] Harmoniser les boutons, menus, champs et curseurs avec les capsules RGB/SEQ.
- [x] Adapter la fenêtre aux petits écrans avec pagination des tranches, vues scènes/sorties/USB et blackout permanent.
- [x] Ajouter des tests de compilation, de disposition et d’interactions sur cinq résolutions.
- [x] Executer la validation manuelle guidee avec tests/manual-validation.ps1 et conserver un rapport sans echec
- [x] Supprimer le chip rgb on/off sur la vue console, il est visible uniquement en vue SORTIES
- [x] Retablir le mode "blind" : programmation sans agir sur les sorties
- [x] Valider sur materiel le sequenceur mono apres correctif : chaque nouveau pas prend le niveau du fader et la sortie mono suit l'intensite du pas
- [x] Valider le menu deroulant FX ControlP5 : MAN / STR / FEU / PUL, sans gel de l UI
- [x] En ruban led RGB, il faut pouvoir atteindre un vrai blanc
- [x] Valider l'edition des steps: clic simple, intensite au fader et couleur a la roue RGB
- [x] Renommer "Sortie/USB" en "Sorties"
- [ ] Préparer le support multi-carte wifi ESP32. 
- [ ] En plus des pins, il faut pouvoir adresser une carte à une tranche
- [x] LE BPM mini du seq est de 20
- [ ] L'etat mono ou RGB est sauvegardable.
