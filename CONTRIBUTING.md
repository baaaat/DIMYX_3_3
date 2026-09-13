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

Il n’existe pas de suite de tests automatisée fournie. Une vérification documentaire ne constitue pas une validation du fonctionnement matériel.
