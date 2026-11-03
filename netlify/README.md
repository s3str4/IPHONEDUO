# Route de Nuit sur Netlify

Ce dossier sert à publier le jeu sur Netlify pour le tester sur téléphone.

## Comment ça marche

À chaque poussée sur `main`, GitHub Actions (`.github/workflows/web.yml`)
lance les tests, exporte la version web, y ajoute `netlify.toml` (ce dossier)
et pousse le tout sur la branche **`netlify`** du dépôt (un seul commit,
remplacé à chaque fois : le dépôt ne grossit pas). Netlify publie cette
branche telle quelle, sans rien construire.

## Brancher Netlify (une seule fois, 2 minutes)

1. Sur https://app.netlify.com : **Add new site → Import an existing project**.
2. **GitHub** → autoriser Netlify → choisir le dépôt **IPHONEDUO**.
3. Réglages du site :
   - **Branch to deploy** : `netlify`
   - **Base directory** : (vide)
   - **Build command** : (vide, `netlify.toml` s'en charge)
   - **Publish directory** : `.`
4. **Deploy**. Netlify donne une adresse du type `https://xxxx.netlify.app`.
   On peut la renommer : *Site configuration → Change site name*
   (ex. `route-de-nuit.netlify.app`).

Ensuite, chaque modification du jeu arrive sur ce site toute seule, environ
deux minutes après la poussée (le temps des tests et de l'export).

## Dépôt privé ?

Possible. Netlify lit les dépôts privés (son application GitHub demande
l'accès au dépôt choisi), et GitHub Actions marche aussi en privé (2 000
minutes gratuites par mois ; un passage prend 2 à 3 minutes). Seul GitHub
Pages (l'ancienne adresse s3str4.github.io) s'arrête : il exige un dépôt
public sur l'offre gratuite. Le site Netlify, lui, reste public : c'est
l'adresse qu'on partage.

## Sur le téléphone

- Ouvrir l'adresse dans Safari, puis **Partager → Sur l'écran d'accueil** :
  le jeu s'ouvre en plein écran comme une app.
- Pas besoin de recharger deux fois : `netlify.toml` demande au navigateur de
  toujours vérifier la dernière version.
- Options utiles dans l'adresse : `?fps` (images par seconde),
  `?police_demo&start_s=17000` (poursuite tout de suite),
  `?lang=en` (anglais).

## Sans GitHub (à la main)

Glisser le dossier de la version web exportée (celui qui contient
`index.html`, avec `netlify.toml` dedans) sur https://app.netlify.com/drop.
