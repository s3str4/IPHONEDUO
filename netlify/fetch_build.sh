#!/bin/sh
# Si Netlify publie la branche « main » (réglage par défaut) au lieu de
# « netlify » : on récupère la version web déjà exportée par GitHub Actions
# sur la branche « netlify » et on la publie (dossier dist/).
set -e
if git fetch --depth=1 origin netlify; then
	rm -rf dist
	mkdir -p dist
	git --work-tree=dist checkout FETCH_HEAD -- .
	ls -la dist
else
	echo "Impossible de lire la branche « netlify » du dépôt."
	echo "Dans Netlify : Site configuration > Build & deploy > Continuous deployment >"
	echo "Branches and deploy contexts > Production branch : netlify"
	exit 1
fi
