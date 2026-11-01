# Route de Nuit — bible du jeu

> Titre provisoire. Document de référence du projet : toute décision de design,
> de direction artistique ou de production est consignée ici. Si le code et la
> bible divergent, on corrige l'un des deux, jamais on ne laisse traîner.

## 1. Le pitch

**Une nuit, une route, atteindre l'aube.**

Il est 3 h du matin. Un appel, une voix qui dit seulement : « Je t'attends à
l'aube. » Tu prends la voiture. La pluie, la radio, les stations-service
éclairées au milieu de rien. Le chrono tourne, la route se divise, et à chaque
bifurcation tu choisis où tu vas finir quand le soleil se lèvera.

Arcade à la OutRun (chrono, checkpoints, embranchements, score) dans une
esthétique PS1 low-poly nocturne, avec une histoire racontée par petites
touches : la radio et des événements étranges sur la route.

- **Plateforme** : iPhone (portrait), jouable à une main.
- **Partie** : 6 à 9 minutes. On rejoue pour le score et pour les autres fins.
- **Moteur** : Godot 4.7, renderer Compatibility (mobile).

## 2. Piliers

1. **Une main, tout de suite.** Pas de tutoriel bavard : on pose le pouce, on roule.
2. **Le flow avant tout.** La vitesse, la pluie, la musique : on doit entrer
   dans un état de conduite hypnotique, comme dans les vidéos YTSLEEP.
3. **La route raconte.** Pas de cinématiques ni de dialogues longs. L'histoire
   passe par la radio, les panneaux, les événements et les fins.
4. **Chaque partie compte.** Un score à battre, une fin à découvrir, un détail
   étrange jamais vu.

## 3. Commandes (une main)

| Geste | Effet |
|---|---|
| Pouce posé sur l'écran | Accélère |
| Pouce glissé à gauche / droite | Braque (position relative au point de contact) |
| Pouce levé | Lâche les gaz, frein moteur ; levé longtemps = freinage |
| Glisser fort en virage à haute vitesse | Dérapage (bonus de score) |
| Double tap | Change de station de radio |

Pas d'accéléromètre par défaut (option dans les réglages).

## 4. Boucle de jeu

### Structure de la route (pyramide OutRun)

5 étapes. Après chaque étape, une bifurcation : gauche ou droite. Soit
**15 segments** au total et **5 destinations** à l'aube.

```
Étape 1                    [A]
Étape 2                 [B]   [C]
Étape 3              [D]   [E]   [F]
Étape 4           [G]   [H]   [I]   [J]
Étape 5        [K]   [L]   [M]   [N]   [O]
Aube         Mer  Ville Barrage Montagne Nulle-part
```

Chaque segment dure environ 80 à 100 s à bonne vitesse et a son ambiance
(forêt, autoroute vide, zone industrielle, col, côte, tunnel…). La gauche est
plus facile, la droite plus dure et mieux payée en score.

### Chrono et stations-service

- Départ avec 75 s au compteur.
- Chaque fin de segment = une **station-service** éclairée : la traverser
  ajoute du temps (bonus dégressif selon l'étape).
- Chrono à zéro = la voiture s'arrête, la nuit gagne. Écran de fin avec score.
- Arriver à l'aube : le temps restant est converti en points, puis la fin joue.

### Score

- **Distance × vitesse** en continu.
- **Frôlage** : dépasser un véhicule de très près.
- **Dérapage** propre sous la pluie.
- **Multiplicateur de chaîne** : il monte tant qu'on enchaîne sans toucher
  personne ni la glissière ; un choc le remet à ×1.
- **Bonus de fin** : temps restant + destination (les plus dures valent plus).

### Obstacles

Trafic (voitures, camions qui éclaboussent), flaques (aquaplaning), bancs de
brouillard, virages serrés, animaux sur la route (rare).

## 5. Événements étranges

Chaque segment a une chance de déclencher un événement. Ils modifient la partie
(temps, score, visibilité) et posent des **marques d'histoire** qui changent
les détails des fins. Exemples :

- **L'auto-stoppeuse** : toujours la même silhouette, à chaque partie un peu
  plus loin sur la route.
- **Le panneau qui se répète** : « Station 2 km » trois fois de suite.
- **La radio qui parle de toi** : l'animateur annonce ta vitesse, ta voiture,
  ta direction.
- **La voiture sans conducteur** qui roule à ta hauteur, phares éteints.
- **La station vide** : tout est allumé, personne, une seule pompe décrochée.
- **Le tunnel trop long** : la musique ralentit, le chrono aussi.

Règle : un événement ne doit jamais être injuste. S'il gêne, il donne quelque
chose (temps, score, information).

## 6. Histoire et fins

On ne dit jamais tout. Qui a appelé ? Pourquoi l'aube ? Chaque fin révèle un
morceau, et les marques d'histoire récoltées en route changent des détails
(qui est là, ce que dit la radio au lever du soleil). La fin « Nulle-part » est
la plus dure et la plus étrange : elle ne s'atteint qu'en ayant vu certains
événements.

Le scénario complet (trame, voix de l'animateur, textes des fins) sera dans
`docs/SCENARIO.md` (étape M2).

## 7. La radio

- **3 stations** : synthwave nocturne, lo-fi pluie, et la station parlée de
  l'animateur de nuit (texte à l'écran + parasites, pas de voix humaine).
- La musique est générée par code (outils hérités de YTSLEEP). Si on veut une
  bande-son marquante pour la sortie, prévoir un compositeur ou des titres sous
  licence (décision à prendre en M3).
- Les tunnels, les ponts et certains événements brouillent la réception.

## 8. Direction artistique

- **PS1 low-poly** : rendu en basse résolution (environ 270 × 480) mis à
  l'échelle sans lissage, sommets légèrement « tremblants », textures sans
  filtrage, brouillard de distance, palette nocturne (bleus, ambres des
  lampadaires, rouges des feux arrière).
- **Caméra** derrière la voiture, en portrait : la route occupe le centre,
  le haut de l'écran montre le ciel et l'horizon qui s'éclaircit vers l'aube.
- **Pluie** : gouttes à l'écran, reflets sur l'asphalte, éclaboussures des camions.
- **L'aube** se lève progressivement pendant toute la partie : la couleur du
  ciel est aussi un indicateur de progression.
- Tout est généré par code et shaders : aucun modèle sculpté à la main.

## 9. Son

Moteur (tonalité liée au régime), pluie (intensité variable), essuie-glaces,
pneus sur le mouillé, souffle des camions, parasites radio, carillon des
stations. Tout synthétisé par code.

## 10. Modèle économique

- **Téléchargement gratuit** : étapes 1 et 2, une destination jouable, score en ligne.
- **Achat unique « Toute la nuit »** (3,99 € envisagé) : toute la pyramide,
  les 5 fins, toutes les stations de radio.
- **Pas de publicité, pas d'abonnement.** Ça casserait l'ambiance.
- Classements Game Center (meilleur score par destination).
- La chaîne YouTube YTSLEEP sert de vitrine (vidéos d'ambiance « Route de Nuit »).

## 11. Technique

- Godot 4.7, renderer Compatibility, export iOS.
- **Route** : générée par morceaux le long d'une courbe procédurale (virages,
  côtes), morceaux recyclés devant la voiture. Chaque segment est décrit par
  un fichier de données (longueur, courbure, décor, trafic, météo).
- **Rendu basse résolution** via un SubViewport, puis mise à l'échelle.
- **Cible** : 60 images/s sur iPhone 11 et plus récents.
- **Compilation iOS** : GitHub Actions sur un Mac de GitHub, puis envoi sur
  TestFlight. Les identifiants Apple sont des secrets du dépôt, jamais dans le code.
- **Tests** : scripts Godot en mode headless (logique de score, chrono,
  bifurcations) et captures d'écran automatiques pour vérifier le rendu.

## 12. Plan de production

| Étape | Contenu | Critère de fin |
|---|---|---|
| **M0** Prototype | Route infinie, voiture, pluie, pouce pour tourner | On roule 2 min sur iPhone ou PC sans bug, et c'est agréable |
| **M1** Tranche jouable | Un chemin complet jusqu'à l'aube : chrono, stations, score, trafic | Une partie complète a un début, une tension et une fin |
| **M1.5** Passe visuelle | Ciel (lune, nuages, étoiles), halos lumineux, gouttes sur l'écran, reflets plus riches, décors variés (ville au loin, pylônes, panneaux), voiture plus belle, police et interface soignées, stations retravaillées | Une capture d'écran donne envie d'acheter le jeu |
| **M2** La nuit entière | Les 15 segments, les bifurcations, les 5 fins, les événements, scénario | Les 5 fins sont atteignables, testées |
| **M3** Radio et son | Les 3 stations, les bruitages, le mixage | Le jeu se joue au casque avec plaisir |
| **M4** iPhone | Compilation automatique, TestFlight, réglages tactiles, performances | Le jeu tourne à 60 images/s sur ton iPhone |
| **M5** Sortie | Menus, achat intégré, Game Center, fiche App Store, confidentialité | Validé par Apple, en ligne |

## 12 bis. Avancement

- **M0 (prototype) : livré, à tester sur iPhone.** Route procédurale infinie
  (virages, collines), voiture arcade, glissières, lampadaires avec flaques de
  lumière et reflets sur la route mouillée, pluie, faisceau des phares,
  caméra portrait, commande au pouce, vitesse et distance à l'écran.
  Banc d'essai headless dans `tests/`. Reste à valider : la sensation au
  pouce sur un vrai téléphone (il faut la compilation iOS de M4, ou un test
  sur PC à la souris en attendant).
- **M1 (tranche jouable) : livré.** Une partie complète de 5 étapes (26 km,
  6 à 7 min) jusqu'à l'aube : chrono, 4 stations-service qui rendent du temps
  (auvent, pompes, boutique, totem, portique « STATION n », panneau à 1 km),
  trafic sur 3 voies (voitures, sportives, camions) qui double et change de
  voie, chocs, frôlages, chaîne et multiplicateur, ciel qui s'éclaircit
  jusqu'à l'aube, écrans de titre / d'arrivée / « la nuit gagne », record
  sauvegardé, rejouer d'une touche.
  - **Équilibrage** (`scripts/run_config.gd`, mesuré par `tools/balance.gd`) :
    une moyenne d'environ 240 km/h suffit tout juste ; le pilote automatique
    (réflexes parfaits) arrive 12 fois sur 12 avec 2 à 40 s d'avance, un
    pilote bridé à 215 km/h ou qui ignore le trafic n'arrive jamais.
  - **Règle anti-mur** : le trafic ne ferme jamais les 3 voies devant le
    joueur (testé, avec un témoin qui prouve que le détecteur voit un mur).
  - **Reste à faire** : la beauté (M1.5), la sensation au pouce sur iPhone.

## 13. Rôles

- **Claude** : direction du projet, game design, code, graphismes et sons
  générés, scénario, tests, compilation, fiche App Store.
- **Christopher** : testeur principal sur iPhone (sensation au pouce, plaisir,
  difficulté), arbitre du goût, compte Apple Developer, paiements et contrats.

## 14. Questions ouvertes

- Titre définitif (vérifier qu'il est libre sur l'App Store).
- Musique générée ou compositeur pour la sortie (M3).
- Prix final et contenu exact de la partie gratuite (M5).
