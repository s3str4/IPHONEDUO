# Route de Nuit

Jeu iPhone d'arcade nocturne en low-poly PS1 : une nuit, une route sous la pluie,
la radio, des stations-service, et l'aube à atteindre avant la fin du chrono.
Score à la OutRun, embranchements, cinq fins.

Titre provisoire. Toute la conception est dans [docs/BIBLE.md](docs/BIBLE.md).

Moteur : Godot 4.7 (renderer Compatibility), export iOS.

## Jouer au prototype (M0)

1. Ouvrir Godot 4.7, « Importer », choisir `project.godot`.
2. Appuyer sur **F5**.

Commandes sur PC :

| Action | Souris (comme le pouce) | Clavier |
|---|---|---|
| Accélérer | bouton gauche enfoncé | Espace / ↑ / Z |
| Tourner | glisser à gauche / à droite | ← → / Q D |
| Freiner | relâcher le bouton (longtemps = frein) | relâcher |

Le glissé est relatif : là où on pose le pouce, les roues sont droites.

Options (Projet > Paramètres > Exécution, ou en ligne de commande après `--`) :
`--seed=N` (autre route), `--autopilot` (la voiture roule seule).

## Tests

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

Route continue et déterministe, voiture conduisible à fond sur plusieurs routes,
virages qui obligent à braquer, frein au pouce levé, tronçons valides,
commande au pouce.

## Organisation

| Dossier | Contenu |
|---|---|
| `scripts/track.gd` | Tracé procédural de la route (coordonnées s, x) |
| `scripts/car_physics.gd` | Conduite arcade, testable sans rendu |
| `scripts/road_builder.gd` | Géométrie des tronçons : route, décor, lampadaires, reflets |
| `scripts/car_view.gd` | Voiture low-poly, feux, faisceau des phares |
| `scripts/thumb_input.gd` | Commande à une main |
| `scripts/main.gd` | Assemblage, caméra, tronçons à la volée |
| `shaders/` | Look PS1 (repris de YTSLEEP), ciel, lumières additives |
| `tests/` | Banc d'essai headless |
