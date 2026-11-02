class_name Scenario
extends RefCounted
## Textes de la nuit : Radio Nuit 98.4 (Marceau, l'animateur), les cinq fins et
## l'épilogue secret. La trame complète est dans docs/SCENARIO.md.
##
## Une réplique tient en 3 lignes de 30 signes environ (police 8 px, 270 px).

const STATION := "RADIO NUIT 98.4"

const RADIO := {
	"start": "3 h 12. Ici Marceau, Radio Nuit. À ceux qui roulent : je reste avec vous jusqu'à l'aube.",
	"call": "Le téléphone a sonné. Une voix : « Je t'attends à l'aube. Tu sais où. » Vous ne savez pas.",
	"fork": "Deux routes devant vous. On ne prend jamais la même deux fois.",
	"low_time": "Le jour ne vous attendra pas. Plus vite.",
	"station": "Une station. Un café, de l'essence, et on repart.",
	# Entrées dans les régions.
	"foret": "La forêt. Plus de lampadaires. Juste vos phares, et les arbres qui écoutent.",
	"port": "Le port. Les grues dorment debout. Les bateaux ne partent qu'à l'aube.",
	"lac": "Le lac. Lou y nageait la nuit, l'été de ses seize ans. Vous vous souvenez ?",
	"faubourgs": "Les faubourgs. Une fenêtre sur dix est allumée. Quelqu'un attend, derrière.",
	"usines": "Les usines ne dorment jamais. Elles respirent du feu.",
	"cote": "La côte. On entend la mer avant de la voir.",
	"periph": "Le périphérique. Mille voitures, et pas une ne va où vous allez.",
	"vallee": "La vallée. Le barrage est au bout. Là où vous vous êtes disputés, Lou et vous.",
	"col": "Le col. Il neige là-haut, même en juin. Lou disait qu'on y voyait l'aube avant tout le monde.",
	"dunes": "Les dunes. La mer est juste derrière. Le ciel pâlit déjà.",
	"centre": "Le centre. Les cafés ouvrent. Quelqu'un pose deux tasses sur une table.",
	"retenue": "La retenue. L'eau est si calme qu'on dirait un deuxième ciel.",
	"tunnels": "Les tunnels. Gardez le cap. Ne comptez pas les lampes.",
	"blanche": "...je ne connais pas cette route. Elle n'est sur aucune carte. Vous êtes sûr ?",
	# Événements étranges.
	"stoppeuse": "Vous l'avez vue ? La fille au bord de la route, le pouce levé. Elle est là chaque nuit. Un peu plus loin.",
	"radio_live": "Message pour la voiture rouge, à %d km/h vers %s : on vous attend. Ne ralentissez pas.",
	"panneau": "Vous êtes ici. Vous êtes ici. Vous êtes ici. Moi aussi, j'ai cru que la route tournait en rond.",
	"fantome": "La voiture à côté de vous, phares éteints... Elle ressemblait à la vôtre. Il y a dix ans.",
	"station_vide": "Une station vide. Tout est allumé. Personne. Une seule pompe décrochée, qui pend.",
	"tunnel": "Ce tunnel est trop long. Le temps s'est arrêté, on dirait. Profitez-en.",
	# La police (voir Police) : Marceau est de votre côté.
	"patrouille": "Entre nous : une patrouille attend plus loin, au bord de la route. Au-dessus de 200, elle vous prend en chasse. Moi, je n'ai rien dit.",
	"patrouille2": "Encore une patrouille devant. Ils écoutent la radio, maintenant. À vous de voir.",
	"poursuite": "Ils ont entendu l'antenne : une voiture rouge qui file vers l'aube. Ne vous laissez pas toucher. Trois fois, c'est le contrôle.",
	"seme_distance": "Plus de gyrophares dans le rétro. Ils vous ont perdu. Respirez.",
	"seme_secteur": "Fin de leur secteur : ils font demi-tour. La nuit est à vous.",
	"arrete": "Contrôle. Papiers, ballon, lampe dans les yeux... Ils vous laissent repartir. Le jour, lui, n'a pas attendu.",
}

## Messages vocaux de Lou, un par tronçon : reçus à la station qui le termine
## (à l'aube pour la dernière étape), gardés dans le carnet de route. Dix ans de
## messages jamais écoutés ; ils se lisent dans n'importe quel ordre.
const LOU_HEADER := "MESSAGE VOCAL — LOU"
const LOU := {
	"autoroute": "C'est moi. Je sais qu'il est tard. Rappelle si tu veux. Ou ne rappelle pas. Mais viens.",
	"foret": "Tu te souviens de la cabane dans la forêt ? Nos noms gravés sous le plancher. Ils y sont encore.",
	"port": "J'ai travaillé au port, la première année. Je regardais partir les bateaux en pensant à toi.",
	"lac": "Le lac a gelé cet hiver. J'ai marché dessus jusqu'au milieu. J'avais envie de te le raconter.",
	"faubourgs": "J'habite là, maintenant. Troisième fenêtre allumée. Je la laisse allumée exprès, au cas où.",
	"usines": "Papa disait que le feu des usines, c'est la nuit qui respire. Tu ne l'as jamais entendu le dire.",
	"cote": "J'ai trouvé un coquillage percé, comme ceux qu'on enfilait sur un fil. Je l'ai gardé pour toi.",
	"periph": "Dix ans que je tourne en rond, comme sur ce périphérique. J'attendais que tu prennes la sortie.",
	"vallee": "Ce qu'on s'est dit au barrage... Je l'ai pensé une seconde. Pas plus. Je te le jure.",
	"col": "Je suis montée au col avec la voiture de papa. Il neigeait. Tu aurais adoré ça.",
	"dunes": "Si tu entends la mer derrière ma voix, c'est que je suis déjà là. Prends ton temps. Pas trop.",
	"centre": "Un café ouvre à cinq heures, au centre. J'y commanderai deux tasses.",
	"retenue": "L'eau est si calme ce soir. On dirait qu'elle attend, elle aussi.",
	"tunnels": "Dans les tunnels, la radio coupe. Alors je t'appelle maintenant, avant.",
	"blanche": "Ce message, je ne l'ai pas encore laissé. Tu l'entends quand même. Ne demande pas comment.",
}

## Les cinq fins : [titre, texte]. %s : détail qui dépend des événements vus.
const ENDINGS := [
	["LA MER", "Le soleil sort de l'eau. Sur la plage, une silhouette en ciré jaune. Lou se retourne. « Tu as mis le temps. » Vous riez tous les deux. Dix ans, ça s'efface en une phrase.%s"],
	["LA VILLE", "Son immeuble. Sa fenêtre, au quatrième, encore allumée. Un mot sur la porte : « Je n'ai pas pu attendre. Mais tu es venu. C'est ce qui compte. »%s"],
	["LE BARRAGE", "Le barrage. Là où tout s'est cassé. Personne. Vous dites à voix haute les mots que vous n'aviez jamais dits. L'eau les garde.%s"],
	["LA MONTAGNE", "L'observatoire, au-dessus des nuages. Lou vous tend un thermos. « Regarde. Ça revient toujours. » Le jour monte, rose, sur toute la vallée.%s"],
	["NULLE PART", "La route blanche s'arrête. Une cabine téléphonique. Le combiné pend. Au bout du fil, votre propre voix : « Je t'attends à l'aube. » C'était vous, depuis le début.%s"],
]

## Détails ajoutés aux fins selon les événements vus.
const DETAILS := {
	"stoppeuse": " Elle a gardé le même blouson que la fille au bord de la route.",
	"fantome": " Sur le parking, une vieille voiture rouge, phares éteints.",
	"radio_live": " À la radio, Marceau dit simplement : « Bien arrivé. »",
	"poursuite": " Loin derrière, sur la route, des gyrophares s'éteignent un à un.",
}

## Épilogue de Nulle Part, quand on a vu au moins EPILOGUE_FLAGS événements.
const EPILOGUE_FLAGS := 4
const EPILOGUE := " Vous raccrochez. Sur le siège passager, la fille au pouce levé vous sourit. C'est Lou, à dix-sept ans. « On rentre ? »"


## Texte complet de la fin `ending`, selon les événements vus.
static func ending_text(ending: int, flags: Dictionary) -> String:
	var details := ""
	if ending == 4 and flags.size() >= EPILOGUE_FLAGS:
		details = EPILOGUE
	else:
		for key in ["stoppeuse", "fantome", "radio_live", "poursuite"]:
			if flags.has(key):
				details = DETAILS[key]
				break
	return Lang.t(ENDINGS[ending][1]) % Lang.t(details)
