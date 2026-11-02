# Export macOS

## Prérequis

- macOS et Processing 4 en mode Java ;
- la bibliothèque ControlP5 installée dans le sketchbook Processing ;
- `processing-java` disponible dans le `PATH`, ou le chemin fourni par
  `PROCESSING_JAVA` ;
- une connexion série ou un réseau Wi-Fi compatible pour la validation des
  sorties physiques.

## Export

Depuis la racine du dépôt sur macOS :

```sh
bash ./macos/export-macos.sh both
```

Variantes possibles :

```sh
bash ./macos/export-macos.sh intel
bash ./macos/export-macos.sh arm64
```

`both` produit deux paquets séparés, Intel et Apple Silicon ; Processing ne
fournit pas une variante universelle unique via sa ligne de commande.

Le résultat est placé dans `build/macos/export-<variante>/`. Le script copie
les JSON versionnés dans `Contents/Java` du paquet exporté ; aucune scène ni
configuration de démonstration n’est générée.

## Validation requise sur Mac

- ouvrir l’application et vérifier l’affichage redimensionnable ;
- charger et enregistrer des scènes et la configuration des sorties ;
- tester les ports série macOS, la découverte Wi-Fi et le routage par carte ;
- vérifier BLACKOUT, BLIND, le séquenceur et les effets ;
- tester l’accès aux fichiers après déplacement de l’application ;
- pour une distribution, signer puis notarier le paquet avec le compte Apple
  du propriétaire.

Le script ne peut pas valider ces points depuis Windows et ne coche donc pas
les tâches matérielles ou de validation utilisateur du `TODO.md`.

## Export GitHub Actions

Le workflow `.github/workflows/macos.yml` exporte actuellement la variante
Intel :

- `dimyx-macos-intel` depuis un runner macOS Intel ;

Dans GitHub, ouvrir **Actions → Processing macOS applications → Run workflow**.
Le fichier ZIP sera disponible comme artefact du workflow. Il n’est ni signé
ni notarié par Apple ; une validation sur Mac reste requise
avant distribution.
