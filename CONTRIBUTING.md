# Contribution et Git

## Organisation du dépôt

La branche principale est `main`. Créer une branche courte pour chaque intervention, par exemple `docs/installation`, `fix/connexion-serie` ou `feature/scenes`. Séparer les modifications de code, de documentation et les réglages de spectacle dans des commits lisibles.

Le dépôt est local ; aucun hébergement distant n’est présupposé. Après création d’un dépôt distant vide, son propriétaire peut le relier avec `git remote add origin <URL>`, puis publier avec `git push -u origin main`.

Pour cloner, imposer le nom du dossier attendu : `git clone <URL> DIMYX_3_3`.

## Cycle de travail

```sh
git status
git switch -c docs/installation
# Effectuer et vérifier les changements.
git diff --check
git diff
git add README.md docs/
git diff --cached
git commit -m "docs: préciser l’installation"
```

Adapter les chemins de `git add` au travail réalisé. Éviter d’inclure par inadvertance des sauvegardes de scènes produites pendant un essai. Les JSON restent suivis volontairement pour conserver les réglages ; examiner leur différence avant chaque commit. Le répertoire `backups/` permet des copies locales exclues de Git.

Les attributs `-text` des `.pde` et `.json` désactivent la conversion automatique des fins de ligne par Git, sans empêcher les différences textuelles. Ne pas appliquer de formatage global à ces fichiers lors d’une intervention documentaire.

## Validation documentaire

- Vérifier les liens relatifs et la concordance des noms de fonctions avec le sketch.
- Exécuter `git diff --check` et examiner `git status`.
- Vérifier que le sketch et les JSON n’ont pas changé.

Empreinte SHA-256 du sketch à l’initialisation documentaire :

```text
FB7AE774DAB83AC2BFF087799F7C525E41676C6589B937A80E6887432220A2F5
```

Sous PowerShell : `Get-FileHash DIMYX_3_3.pde -Algorithm SHA256`.

## Validation d’une future évolution fonctionnelle

Travailler sur une copie des JSON avant les essais qui enregistrent ou suppriment des scènes.

1. Ouvrir et compiler le sketch dans Processing avec ControlP5 ; noter les versions utilisées.
2. Vérifier les 10 tranches, les modes mono/RGB, les faders et les effets.
3. Créer, enregistrer, rappeler et supprimer une scène ; vérifier les transitions et la pagination.
4. Vérifier l’ajout et l’édition des pas, l’activation du séquenceur et le tempo.
5. Redémarrer et vérifier la persistance des scènes, des noms et des sorties.
6. Avec le matériel compatible, vérifier la détection, les commandes de sortie, le blackout, la déconnexion et la reprise de scène.
7. Déplacer une scène avec MONTER/DESCENDRE : tester sans sélection, avec une seule scène, aux extrémités et entre les positions 8 et 9. Vérifier que la sélection suit la page, que la scène active (et celle à reprendre après déconnexion) reste la même et que l’ordre persiste au redémarrage. Tester aussi pendant une transition.

Il n’existe pas de suite de tests automatisée fournie. Une vérification documentaire ne constitue pas une validation du fonctionnement matériel.

Pour l’interface et le clonage : vérifier les capsules RGB/SEQ sur les 10 tranches (OFF sombre à gauche, ON vif à droite), au clic, au rappel de scène et au blackout. Cloner une tranche mono puis RGB avec effets et plusieurs pas vers une destination déjà remplie ; vérifier ses niveaux, sa couleur, son tempo, son redémarrage au premier pas et la conservation de son nom et de ses sorties. Modifier un pas copié et vérifier que la source reste identique. Tester ANNULER, une source sans pas, une destination en édition de pas et le refus pendant une transition. Enregistrer avec REC puis rappeler et redémarrer pour vérifier la persistance.

Pour la combinaison séquenceur/effets : créer deux pas de couleurs et intensités différentes, activer SEQ RUN puis essayer STR, PUL et FEU. Vérifier que les pas continuent sans redémarrage au changement d’effet, que BPM et FREQ restent accessibles ensemble et qu’un pas nul reste éteint. Arrêter SEQ RUN et vérifier le retour au niveau manuel avec le même effet. Enregistrer/rappeler la scène, tester une transition et charger une ancienne scène `fx: 4`. Vérifier aussi le blackout avec SEQ RUN et un effet actifs.
