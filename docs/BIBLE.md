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

Chaque segment dure environ 80 s à bonne vitesse et a son ambiance
(`scripts/route_map.gd`) :

| Étape | Tronçons (de gauche à droite) |
|---|---|
| 1 | L'Autoroute |
| 2 | La Forêt · Le Port |
| 3 | Le Lac · Les Faubourgs · Les Usines |
| 4 | La Côte · Le Périphérique · La Vallée · Le Col |
| 5 | Les Dunes · Le Centre · La Retenue · Les Tunnels · La Route Blanche |

La gauche est plus facile, la droite plus dure (trafic, camions, virages,
brouillard, neige) et mieux payée : bonus de destination de 0 à 25 000 points.

**La bifurcation** : juste après le portique de la station, un terre-plein
sépare la route sur 360 m. Le côté où l'on est à son nez décide de la suite ;
y arriver au milieu, c'est le percuter. Des panneaux (vert à gauche, bleu à
droite) annoncent les directions à 600 m et sous le portique, et elles
s'affichent en haut de l'écran 1,2 km avant. La route est droite et le trafic
quitte la voie du milieu à l'approche.

### Chrono et stations-service

- Départ avec 88 s au compteur (voir `scripts/run_config.gd`).
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

Six événements, posés par `scripts/event_director.gd`, laissent des
**marques d'histoire** qui changent les détails des fins (détail dans
`docs/SCENARIO.md`) :

- **L'auto-stoppeuse** : ciré jaune, pouce levé, à chaque partie un peu plus loin.
- **La radio parle de toi** : Marceau annonce ta vitesse et ta région.
- **Le panneau qui se répète** : « VOUS ÊTES ICI », trois fois de suite.
- **La station vide** : la station 3 baigne dans une lumière bleue, personne.
- **La voiture fantôme** : une sportive rouge, phares éteints, roule à ta
  hauteur puis s'évanouit (on ne peut pas la percuter).
- **Le tunnel trop long** (Les Tunnels) : le chrono s'arrête.

Règle : un événement ne doit jamais être injuste. S'il gêne, il donne quelque
chose (temps, score, information).

## 6. Histoire et fins

On ne dit jamais tout. La voix au téléphone, c'est Lou, la sœur du joueur,
perdue de vue depuis dix ans. Chaque fin révèle un morceau, et les marques
d'histoire changent des détails. « Nulle Part » (toujours à droite) est la
plus dure et la plus étrange ; avec au moins 4 événements vus, elle cache un
épilogue secret.

Le scénario complet est dans `docs/SCENARIO.md`.

## 7. La radio

- **Radio Nuit 98.4** : musique synthwave, et Marceau qui parle (texte à
  l'écran, tapé lettre à lettre, avec un grésillement ; pas de voix humaine).
- **Bleu Nuit 103.7** : lo-fi jazzy sous la pluie.
- **Radio éteinte** : le moteur, la pluie, le vent.
- On change de station d'un **double tap**.
- La musique est générée par code (`tools/make_audio.py`). Pour une bande-son
  marquante à la sortie, prévoir un compositeur ou des titres sous licence
  (décision avant M5).

## 8. Direction artistique

Depuis M3 : **néo-rétro haute définition**, plus de look PS1.

- **Nuit mouillée** : la chaussée est un miroir (caméra de réflexion), les
  lampadaires y laissent de longues traînées, les cônes de lumière se
  remplissent de pluie, des gouttes coulent sur l'écran.
- **Lumière par pixel** : les 16 lumières les plus proches (sodium orange,
  LED blanches, néons des stations, portiques, tunnels) éclairent route,
  décors et voiture, avec de vrais reflets ; au loin, une lumière précalculée
  prend le relais. Bloom, courbe de tonalité, étalonnage (ombres bleutées,
  lumières chaudes), vignette, grain, flou radial à grande vitesse.
- **Voiture** : sportive « coin de fromage » des années 80 en surfaces
  lissées, peinture laquée qui renvoie la ville.
- **Typographie néon** : Monoton (logo), Audiowide (chiffres, titres),
  Rajdhani (textes), avec une lueur.
- **Caméra** derrière la voiture, en portrait ; **l'aube** se lève pendant
  toute la partie et sert de jauge d'avancement.
- Tout est généré par code et shaders : aucun modèle sculpté à la main.

## 9. Son

Tout est synthétisé par code (`tools/make_audio.py`, aucun échantillon
externe) : moteur en deux couches qui suit une boîte à 6 rapports, vent et
pneus mouillés selon la vitesse, pluie selon la météo, écho dans les tunnels,
chocs, frôlements, terre-plein, carillon des stations, grésillement radio, et
deux musiques en boucle sans couture (synthwave 104 bpm, lo-fi 78 bpm).

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
- **Rendu** : 3D en pleine résolution (interface en coordonnées 270 × 480
  mises à l'échelle), une passe de réflexion à demi-résolution. Sur iPhone,
  baisser la résolution 3D si besoin (`scaling_3d_scale`, M4).
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
  - **Reste à faire** : la sensation au pouce sur iPhone.
- **M1.5 (passe visuelle) : livré.**
  - Voiture : sportive « coin de fromage » années 80 (ouïes latérales, phares
    escamotables, bandeau de feux arrière), ombrage figé par face sur tous les
    véhicules.
  - Ciel : étoiles qui scintillent, lune et son halo, nuages qui dérivent,
    éclairés par la ville et rosis par l'aube, deux chaînes de montagnes, ville
    illuminée à l'horizon.
  - Lumière : halos face caméra (lampadaires, feux, totem, portiques, pylônes),
    reflet du ciel sur la route mouillée, gouttes sur l'écran, vignette.
  - Décors : ligne haute tension (pylônes, câbles, feu rouge), ponts éclairés,
    panneaux publicitaires lumineux qui glissent des indices de l'histoire.
  - Interface : polices pixel libres (Press Start 2P, Pixelify Sans, OFL),
    bandeaux en dégradé, jauge des étapes de la nuit à l'aube, compteur
    segmenté, logo du titre, caméra qui tourne autour de la voiture au titre.
  - Performance : les tronçons (35 ms chacun) se construisent en tâche de
    fond ; aucune image sans route devant la voiture sur une minute à fond.
  - Reste pour plus tard : bruitages et musique (M3), vraie mesure de
    performance sur iPhone (M4).

- **M2 (la nuit entière) : livré.**
  - Pyramide de 15 tronçons, 4 bifurcations à terre-plein, 5 destinations.
    Chaque tronçon a sa propre route (même tronçon = même forme, quel que soit
    le chemin) et son ambiance : lampadaires sodium ou LED (ou aucun), forêt
    dense, eau (lac, mer, port), maisons, tours aux fenêtres allumées,
    conteneurs et grues, usines et torchères, tunnels, neige, brouillard.
  - Radio Nuit 98.4 : Marceau commente la nuit (texte tapé lettre à lettre),
    titre de chaque région à l'écran.
  - Six événements étranges, cinq fins et un épilogue secret ; sauvegarde
    des fins découvertes et du nombre de parties.
  - Trafic adapté aux bifurcations (voie du milieu dégagée, pas de nouveaux
    véhicules le long du terre-plein, règle anti-mur sur 2 voies).
  - Équilibrage : le pilote automatique atteint chacune des 5 destinations
    (29 parties sur 30) ; un pilote à 215 km/h ou qui ignore le trafic, jamais.
  - 112 tests, dont : chaque chemin mène à la bonne fin, rien n'est généré
    au-delà d'une bifurcation non choisie, le terre-plein retient la voiture,
    toutes les lettres des textes existent dans la police.

- **M3 (beauté et son) : livré.**
  - Abandon du look PS1 au profit d'un rendu haute définition : route miroir,
    éclairage par pixel, cônes de lumière, bloom et étalonnage, voiture
    laquée en surfaces lissées, berlines du trafic redessinées, sapins plus
    fournis, polices néon.
  - Son complet et deux stations de musique (voir § 7 et § 9), double tap
    pour changer de station.
  - Défauts trouvés en route : normales retournées qui éteignaient
    l'éclairage, terrain vu par en dessous qui noircissait le reflet, pont
    éclairé comme un plafond, gouttes trop proches qui barraient l'écran,
    double tap compté deux fois.
  - À mesurer en M4 : les performances sur iPhone (deux rendus par image,
    16 lumières par pixel) ; réglages de repli prévus (réflexion plus
    petite, moins de lumières).

## 13. Rôles

- **Claude** : direction du projet, game design, code, graphismes et sons
  générés, scénario, tests, compilation, fiche App Store.
- **Christopher** : testeur principal sur iPhone (sensation au pouce, plaisir,
  difficulté), arbitre du goût, compte Apple Developer, paiements et contrats.

## 14. Questions ouvertes

- Titre définitif (vérifier qu'il est libre sur l'App Store).
- Musique générée ou compositeur pour la sortie (M3).
- Prix final et contenu exact de la partie gratuite (M5).
