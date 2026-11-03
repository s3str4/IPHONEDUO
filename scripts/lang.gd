class_name Lang
extends RefCounted
## Langue du jeu : le français est la langue d'écriture, chaque texte affiché
## passe par Lang.t(), qui renvoie sa version anglaise quand le jeu est en
## anglais. La clé est le texte français exact ; les gabarits (%d, %s) se
## traduisent AVANT d'être remplis : Lang.t("FRÔLÉ +%d") % points.
##
## tests/run_tests.gd vérifie que chaque texte du code a sa traduction, avec
## les mêmes gabarits, et qu'aucun écran en anglais ne montre du français.

## "fr" ou "en".
static var code := "fr"


static func t(s: String) -> String:
	if code == "fr":
		return s
	return EN.get(s, s)


## Langue du système (navigateur, téléphone) : anglais si ce n'est pas du français.
static func detect() -> String:
	return "fr" if OS.get_locale_language() == "fr" else "en"


## Applique le réglage ("" : langue du système).
static func apply(setting: String) -> void:
	code = setting if setting in ["fr", "en"] else detect()


## Nombre groupé par milliers : 12 345 en français, 12,345 en anglais.
static func group(n: int) -> String:
	var sep := "," if code == "en" else " "
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = sep + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


const EN := {
	# --- Interface en course -------------------------------------------------------
	"TEMPS": "TIME",
	"SCORE": "SCORE",
	"ÉTAPE 1/5": "STAGE 1/5",
	"ÉTAPE %d/%d": "STAGE %d/%d",
	"KM/H": "KM/H",
	"TURBO": "TURBO",
	"PAUSE": "PAUSE",
	"TOUCHE POUR REPRENDRE": "TAP TO RESUME",
	"TOUCHE POUR REJOUER": "TAP TO PLAY AGAIN",
	"TITRE": "TITLE",
	"ROUTE": "NIGHT",
	"DE NUIT": "ROAD",
	"CARNET": "LOGBOOK",
	"GARAGE": "GARAGE",
	"NUIT DU JOUR": "DAILY NIGHT",
	"RÉGLAGES": "SETTINGS",
	"TURBO PRÊT : GLISSE LE POUCE VERS LE HAUT": "TURBO READY: SWIPE YOUR THUMB UP",
	"FRÔLÉ +%d": "CLOSE CALL +%d",
	"CHAÎNE PERDUE": "CHAIN LOST",
	"Atteins l'aube avant la fin du chrono.\nRECORD %s   |   FINS %d/%d":
			"Reach dawn before the clock runs out.\nBEST %s   |   ENDINGS %d/%d",
	"POSE TON POUCE": "PUT YOUR THUMB DOWN",
	"NUIT DU %s": "NIGHT OF %s",
	"GLISSE LE POUCE POUR TOURNER": "SLIDE YOUR THUMB TO STEER",
	"LÈVE LE POUCE POUR FREINER": "LIFT YOUR THUMB TO BRAKE",
	"DOUBLE TAP : CHANGER DE RADIO": "DOUBLE TAP: CHANGE STATION",
	"CHAQUE STATION RAJOUTE DU TEMPS": "EVERY GAS STATION ADDS TIME",
	"AU TERRE-PLEIN, CHOISIS TON CÔTÉ": "AT THE SPLIT, PICK YOUR SIDE",
	"STATION %d": "STATION %d",
	"NOUVEAU — ": "NEW — ",
	"%s\n\n%s\n\n%sSCORE %s\nBONUS TEMPS %s\nÉVÉNEMENTS %d/%d\n%s\n+%s CRÉDITS%s":
			"%s\n\n%s\n\n%sSCORE %s\nTIME BONUS %s\nEVENTS %d/%d\n%s\n+%s CREDITS%s",
	"NOUVELLE FIN ! ": "NEW ENDING! ",
	"NOUVEAU RECORD !": "NEW RECORD!",
	"RECORD %s": "BEST %s",
	"  —  nouvelle teinte au garage": "  —  new paint in the garage",
	"LA NUIT\nGAGNE": "THE NIGHT\nWINS",
	"\nÉTAPE %d SUR %d\n%.1f KM\n\nSCORE %s\n\n%s\n+%s CRÉDITS":
			"\nSTAGE %d OF %d\n%.1f KM\n\nSCORE %s\n\n%s\n+%s CREDITS",

	# --- Menus ------------------------------------------------------------------------
	"RETOUR": "BACK",
	"CARNET DE ROUTE": "LOGBOOK",
	"FINS  %d / %d": "ENDINGS  %d / %d",
	"%s  —  record %s": "%s  —  best %s",
	"MESSAGES DE LOU  %d / %d": "LOU'S MESSAGES  %d / %d",
	"— pas encore écouté —": "— not heard yet —",
	"ÉVÉNEMENTS  %d / %d": "EVENTS  %d / %d",
	"???  —  pas encore vu": "???  —  not seen yet",
	"VOITURE": "CAR",
	"  —  chaque fin débloque une teinte": "  —  every ending unlocks a paint",
	"RECORDS": "RECORDS",
	"Meilleur score : %s": "Best score: %s",
	"Nuit du jour : %s": "Daily night: %s",
	"Parties jouées : %d": "Runs played: %d",
	"MUSIQUE": "MUSIC",
	"EFFETS": "SOUND EFFECTS",
	"SENSIBILITÉ DU POUCE": "THUMB SENSITIVITY",
	"QUALITÉ GRAPHIQUE": "GRAPHICS QUALITY",
	"SOBRE": "LOW",
	"NORMALE": "MEDIUM",
	"HAUTE": "HIGH",
	"Sobre : sans reflet de la route, pour les iPhone plus anciens.":
			"Low: no road reflections, for older iPhones.",
	"LANGUE": "LANGUAGE",
	"AUTO": "AUTO",
	"CRÉDITS  %s   —   1 crédit tous les 100 points": "CREDITS  %s   —   1 credit per 100 points",
	"%s  —  NIVEAU %d/%d": "%s  —  LEVEL %d/%d",
	"AMÉLIORER — %s": "UPGRADE — %s",
	"OPTIONS": "OPTIONS",
	"OUI": "ON",
	"%s : %s": "%s: %s",
	"« %s »": "“%s”",
	"%s\n« %s »": "%s\n“%s”",
	"FRANÇAIS": "FRANÇAIS",
	"ENGLISH": "ENGLISH",
	"NON": "OFF",
	"COULEUR DU NÉON": "NEON COLOR",
	"L'auto-stoppeuse": "The hitchhiker",
	"La radio parle de toi": "The radio talks about you",
	"Le panneau qui se répète": "The sign that repeats",
	"La station vide": "The empty station",
	"La voiture fantôme": "The ghost car",
	"Le tunnel trop long": "The tunnel that's too long",
	"toujours à gauche": "always left",
	"une fois à droite": "right once",
	"deux fois à droite": "right twice",
	"trois fois à droite": "right three times",
	"toujours à droite": "always right",

	# --- Garage -----------------------------------------------------------------------
	"MOTEUR": "ENGINE",
	"Vitesse de pointe +1,5 % par niveau": "Top speed +1.5% per level",
	"PNEUS PLUIE": "RAIN TIRES",
	"Braquage +6 %, moins de dérive en virage": "Steering +6%, less drift in corners",
	"Jauge +15 % plus rapide, +0,3 s de turbo": "Gauge fills 15% faster, +0.3 s of turbo",
	"CHÂSSIS": "CHASSIS",
	"Moins de vitesse perdue dans les chocs": "Less speed lost in crashes",
	"AILERON": "SPOILER",
	"NÉON SOUS CAISSE": "UNDERGLOW NEON",
	"JANTES CHROMÉES": "CHROME RIMS",
	"ROUGE NUIT": "NIGHT RED",
	"BLEU MER": "SEA BLUE",
	"BLANC VILLE": "CITY WHITE",
	"VERT BARRAGE": "DAM GREEN",
	"OR MONTAGNE": "MOUNTAIN GOLD",
	"NOIR NULLE PART": "NOWHERE BLACK",

	# --- Radio --------------------------------------------------------------------------
	"RADIO NUIT 98.4": "NIGHT RADIO 98.4",
	"ITALO NUIT 89.2": "ITALO NIGHT 89.2",
	"EURO 90 FM": "EURO 90 FM",
	"BALLADES FM 101.5": "FM BALLADS 101.5",
	"RADIO ÉTEINTE": "RADIO OFF",

	# --- Route : régions, fins, panneaux -------------------------------------------------
	"L'AUTOROUTE": "THE MOTORWAY",
	"LA FORÊT": "THE FOREST",
	"LE PORT": "THE HARBOR",
	"LE LAC": "THE LAKE",
	"LES FAUBOURGS": "THE OUTSKIRTS",
	"LES USINES": "THE FACTORIES",
	"LA CÔTE": "THE COAST",
	"LE PÉRIPHÉRIQUE": "THE RING ROAD",
	"LA VALLÉE": "THE VALLEY",
	"LE COL": "THE PASS",
	"LES DUNES": "THE DUNES",
	"LE CENTRE": "DOWNTOWN",
	"LA RETENUE": "THE RESERVOIR",
	"LES TUNNELS": "THE TUNNELS",
	"LA ROUTE BLANCHE": "THE WHITE ROAD",
	"LA MER": "THE SEA",
	"LA VILLE": "THE CITY",
	"LE BARRAGE": "THE DAM",
	"LA MONTAGNE": "THE MOUNTAIN",
	"NULLE PART": "NOWHERE",
	"MOTEL DE L'AUBE\n12 km": "DAWN MOTEL\n12 km",
	"RADIO NUIT\n98.4 FM": "NIGHT RADIO\n98.4 FM",
	"CAFÉ\n24 H / 24": "DINER\nOPEN 24 H",
	"VOUS N'ÊTES\nPAS SEUL": "YOU ARE\nNOT ALONE",
	"LA MER\n> 40 km": "THE SEA\n> 40 km",
	"ELLE VOUS\nATTEND": "SHE IS\nWAITING",
	"STATION\n1 km": "GAS\n1 km",
	"AUBE": "DAWN",

	# --- Police -------------------------------------------------------------------------
	"POURSUITE": "PURSUIT",
	"PARTAGER": "SHARE",
	"STYLE : %s": "STYLE: %s",
	"NÉON": "NEON",
	"PIXEL ART": "PIXEL ART",
	"%s POINTS": "%s POINTS",
	"J'AI VU L'AUBE": "I SAW THE DAWN",
	"LA NUIT GAGNE": "THE NIGHT WINS",
	"Étape %d sur %d — %.1f km": "Stage %d of %d — %.1f km",
	"J'ai vu l'aube sur %s dans Route de Nuit : %s points.": "I saw the dawn over %s in Night Road: %s points.",
	"La nuit m'a rattrapé à l'étape %d dans Route de Nuit : %s points.": "The night caught me at stage %d in Night Road: %s points.",
	"LE FANTÔME A PRIS L'AUTRE ROUTE": "THE GHOST TOOK THE OTHER ROAD",
	"FANTÔME DU RECORD : %s": "RECORD GHOST: %s",
	"POURSUITE !": "PURSUIT!",
	"ELLE CHARGE": "RAM INCOMING",
	"%d M DERRIÈRE": "%d M BEHIND",
	"DEVANT VOUS": "AHEAD OF YOU",
	"QUAND ELLE CHARGE, CHANGE DE VOIE": "WHEN THEY RAM, SWITCH LANES",
	"TOUCHÉ %d/%d": "HIT %d/%d",
	"ARRÊTÉ !": "BUSTED!",
	"SEMÉE ! +%s": "ESCAPED! +%s",
	"TURBO PLEIN": "TURBO FULL",
	"La poursuite": "The pursuit",
	"Poursuites semées : %d   —   arrêté %d fois": "Pursuits escaped: %d   —   busted %d times",
	"Entre nous : une patrouille attend plus loin, au bord de la route. Au-dessus de 200, elle vous prend en chasse. Moi, je n'ai rien dit.":
			"Between us: there's a patrol car waiting up ahead by the road. Go over 200 and they'll come after you. You didn't hear it from me.",
	"Encore une patrouille devant. Ils écoutent la radio, maintenant. À vous de voir.":
			"Another patrol up ahead. They listen to the radio now. Your call.",
	"Ils ont entendu l'antenne : une voiture rouge qui file vers l'aube. Ne vous laissez pas toucher. Trois fois, c'est le contrôle.":
			"They heard it on air: a red car racing toward dawn. Don't let them touch you. Three hits and they pull you over.",
	"Plus de gyrophares dans le rétro. Ils vous ont perdu. Respirez.":
			"No more flashing lights in the mirror. They lost you. Breathe.",
	"Fin de leur secteur : ils font demi-tour. La nuit est à vous.":
			"End of their patch: they're turning back. The night is yours.",
	"Contrôle. Papiers, ballon, lampe dans les yeux... Ils vous laissent repartir. Le jour, lui, n'a pas attendu.":
			"Pulled over. License, breathalyzer, flashlight in your eyes... They let you go. Daylight didn't wait.",
	" Loin derrière, sur la route, des gyrophares s'éteignent un à un.":
			" Far behind, on the road, flashing lights go out one by one.",
	"VOUS ÊTES\nICI": "YOU ARE\nHERE",

	# --- Radio Nuit : Marceau ---------------------------------------------------------------
	"3 h 12. Ici Marceau, Radio Nuit. À ceux qui roulent : je reste avec vous jusqu'à l'aube.":
			"3:12 a.m. This is Marceau, Night Radio. To everyone still driving: I'm with you until dawn.",
	"Le téléphone a sonné. Une voix : « Je t'attends à l'aube. Tu sais où. » Vous ne savez pas.":
			"The phone rang. A voice: “I'll wait for you at dawn. You know where.” You don't.",
	"Deux routes devant vous. On ne prend jamais la même deux fois.":
			"Two roads ahead. You never take the same one twice.",
	"Le jour ne vous attendra pas. Plus vite.":
			"Daylight won't wait for you. Faster.",
	"Une station. Un café, de l'essence, et on repart.":
			"A gas station. Coffee, fuel, and back on the road.",
	"La forêt. Plus de lampadaires. Juste vos phares, et les arbres qui écoutent.":
			"The forest. No more streetlights. Just your headlights, and the trees listening.",
	"Le port. Les grues dorment debout. Les bateaux ne partent qu'à l'aube.":
			"The harbor. The cranes sleep standing up. The boats only leave at dawn.",
	"Le lac. Lou y nageait la nuit, l'été de ses seize ans. Vous vous souvenez ?":
			"The lake. Lou swam here at night, the summer she was sixteen. Remember?",
	"Les faubourgs. Une fenêtre sur dix est allumée. Quelqu'un attend, derrière.":
			"The outskirts. One window in ten is lit. Someone's waiting behind it.",
	"Les usines ne dorment jamais. Elles respirent du feu.":
			"The factories never sleep. They breathe fire.",
	"La côte. On entend la mer avant de la voir.":
			"The coast. You hear the sea before you see it.",
	"Le périphérique. Mille voitures, et pas une ne va où vous allez.":
			"The ring road. A thousand cars, and not one going where you're going.",
	"La vallée. Le barrage est au bout. Là où vous vous êtes disputés, Lou et vous.":
			"The valley. The dam is at the end of it. Where you and Lou had that fight.",
	"Le col. Il neige là-haut, même en juin. Lou disait qu'on y voyait l'aube avant tout le monde.":
			"The pass. It snows up there, even in June. Lou said you could see dawn there before anyone else.",
	"Les dunes. La mer est juste derrière. Le ciel pâlit déjà.":
			"The dunes. The sea is just behind them. The sky's already turning pale.",
	"Le centre. Les cafés ouvrent. Quelqu'un pose deux tasses sur une table.":
			"Downtown. The diners are opening. Someone sets two cups on a table.",
	"La retenue. L'eau est si calme qu'on dirait un deuxième ciel.":
			"The reservoir. The water's so still it looks like a second sky.",
	"Les tunnels. Gardez le cap. Ne comptez pas les lampes.":
			"The tunnels. Hold your line. Don't count the lights.",
	"...je ne connais pas cette route. Elle n'est sur aucune carte. Vous êtes sûr ?":
			"...I don't know this road. It's not on any map. Are you sure?",
	"Vous l'avez vue ? La fille au bord de la route, le pouce levé. Elle est là chaque nuit. Un peu plus loin.":
			"Did you see her? The girl by the road, thumb out. She's there every night. A little further on.",
	"Message pour la voiture rouge, à %d km/h vers %s : on vous attend. Ne ralentissez pas.":
			"Message for the red car doing %d km/h toward %s: someone's waiting for you. Don't slow down.",
	"Vous êtes ici. Vous êtes ici. Vous êtes ici. Moi aussi, j'ai cru que la route tournait en rond.":
			"You are here. You are here. You are here. I thought the road was going in circles too.",
	"La voiture à côté de vous, phares éteints... Elle ressemblait à la vôtre. Il y a dix ans.":
			"The car next to you, lights off... It looked like yours. Ten years ago.",
	"Une station vide. Tout est allumé. Personne. Une seule pompe décrochée, qui pend.":
			"An empty gas station. Every light on. Nobody. One pump off its hook, hanging.",
	"Ce tunnel est trop long. Le temps s'est arrêté, on dirait. Profitez-en.":
			"This tunnel is too long. Time seems to have stopped. Make the most of it.",

	# --- Messages de Lou ---------------------------------------------------------------------
	"MESSAGE VOCAL — LOU": "VOICEMAIL — LOU",
	"C'est moi. Je sais qu'il est tard. Rappelle si tu veux. Ou ne rappelle pas. Mais viens.":
			"It's me. I know it's late. Call back if you want. Or don't. But come.",
	"Tu te souviens de la cabane dans la forêt ? Nos noms gravés sous le plancher. Ils y sont encore.":
			"Remember the shack in the forest? Our names carved under the floor. They're still there.",
	"J'ai travaillé au port, la première année. Je regardais partir les bateaux en pensant à toi.":
			"I worked at the harbor, that first year. I watched the boats leave and thought about you.",
	"Le lac a gelé cet hiver. J'ai marché dessus jusqu'au milieu. J'avais envie de te le raconter.":
			"The lake froze this winter. I walked out to the middle. I wanted to tell you about it.",
	"J'habite là, maintenant. Troisième fenêtre allumée. Je la laisse allumée exprès, au cas où.":
			"I live here now. Third lit window. I leave it on on purpose, just in case.",
	"Papa disait que le feu des usines, c'est la nuit qui respire. Tu ne l'as jamais entendu le dire.":
			"Dad used to say the factory fires were the night breathing. You never heard him say it.",
	"J'ai trouvé un coquillage percé, comme ceux qu'on enfilait sur un fil. Je l'ai gardé pour toi.":
			"I found a shell with a hole in it, like the ones we used to string. I kept it for you.",
	"Dix ans que je tourne en rond, comme sur ce périphérique. J'attendais que tu prennes la sortie.":
			"Ten years going in circles, like this ring road. I was waiting for you to take the exit.",
	"Ce qu'on s'est dit au barrage... Je l'ai pensé une seconde. Pas plus. Je te le jure.":
			"What we said at the dam... I meant it for one second. No more. I swear.",
	"Je suis montée au col avec la voiture de papa. Il neigeait. Tu aurais adoré ça.":
			"I drove Dad's car up to the pass. It was snowing. You would have loved it.",
	"Si tu entends la mer derrière ma voix, c'est que je suis déjà là. Prends ton temps. Pas trop.":
			"If you hear the sea behind my voice, I'm already there. Take your time. Not too much.",
	"Un café ouvre à cinq heures, au centre. J'y commanderai deux tasses.":
			"A diner opens at five, downtown. I'll order two cups.",
	"L'eau est si calme ce soir. On dirait qu'elle attend, elle aussi.":
			"The water's so calm tonight. Like it's waiting too.",
	"Dans les tunnels, la radio coupe. Alors je t'appelle maintenant, avant.":
			"The radio cuts out in the tunnels. So I'm calling you now, before.",
	"Ce message, je ne l'ai pas encore laissé. Tu l'entends quand même. Ne demande pas comment.":
			"I haven't left this message yet. You're hearing it anyway. Don't ask how.",

	# --- Les fins ----------------------------------------------------------------------------
	"Le soleil sort de l'eau. Sur la plage, une silhouette en ciré jaune. Lou se retourne. « Tu as mis le temps. » Vous riez tous les deux. Dix ans, ça s'efface en une phrase.%s":
			"The sun rises out of the water. On the beach, a figure in a yellow raincoat. Lou turns around. “Took you long enough.” You both laugh. Ten years, gone in one sentence.%s",
	"Son immeuble. Sa fenêtre, au quatrième, encore allumée. Un mot sur la porte : « Je n'ai pas pu attendre. Mais tu es venu. C'est ce qui compte. »%s":
			"Her building. Her window, fourth floor, still lit. A note on the door: “I couldn't wait. But you came. That's what matters.”%s",
	"Le barrage. Là où tout s'est cassé. Personne. Vous dites à voix haute les mots que vous n'aviez jamais dits. L'eau les garde.%s":
			"The dam. Where everything broke. No one here. You say out loud the words you never said. The water keeps them.%s",
	"L'observatoire, au-dessus des nuages. Lou vous tend un thermos. « Regarde. Ça revient toujours. » Le jour monte, rose, sur toute la vallée.%s":
			"The observatory, above the clouds. Lou hands you a thermos. “Look. It always comes back.” Pink daylight rises over the whole valley.%s",
	"La route blanche s'arrête. Une cabine téléphonique. Le combiné pend. Au bout du fil, votre propre voix : « Je t'attends à l'aube. » C'était vous, depuis le début.%s":
			"The white road ends. A phone booth. The receiver hangs loose. On the line, your own voice: “I'll wait for you at dawn.” It was you, all along.%s",
	" Elle a gardé le même blouson que la fille au bord de la route.":
			" She's wearing the same jacket as the girl by the road.",
	" Sur le parking, une vieille voiture rouge, phares éteints.":
			" In the parking lot, an old red car, lights off.",
	" À la radio, Marceau dit simplement : « Bien arrivé. »":
			" On the radio, Marceau just says: “Safe and sound.”",
	" Vous raccrochez. Sur le siège passager, la fille au pouce levé vous sourit. C'est Lou, à dix-sept ans. « On rentre ? »":
			" You hang up. In the passenger seat, the hitchhiker smiles at you. It's Lou, at seventeen. “Shall we go home?”",

	# --- Répliques courtes (en course) ---------------------------------------------------
	"Radio Nuit, 3 h 12. Je reste avec vous jusqu'à l'aube.": "Night Radio, 3:12 a.m. I'm with you until dawn.",
	"« Je t'attends à l'aube. Tu sais où. »": "“I'll wait for you at dawn. You know where.”",
	"Deux routes. À vous de choisir.": "Two roads. Your call.",
	"Le jour n'attendra pas. Plus vite.": "Daylight won't wait. Faster.",
	"Une station. Du café, et on repart.": "A gas station. Coffee, and back on the road.",
	"La forêt. Juste vos phares.": "The forest. Just your headlights.",
	"Le port. Les bateaux partent à l'aube.": "The harbor. The boats leave at dawn.",
	"Le lac où Lou nageait, à seize ans.": "The lake where Lou swam, at sixteen.",
	"Une fenêtre allumée. Quelqu'un attend.": "A lit window. Someone's waiting.",
	"Les usines respirent du feu.": "The factories breathe fire.",
	"On entend la mer avant de la voir.": "You hear the sea before you see it.",
	"Mille voitures. Aucune ne va où vous allez.": "A thousand cars. None going your way.",
	"Le barrage, au bout. Là où tout s'est cassé.": "The dam, at the end. Where it all broke.",
	"Là-haut, on voit l'aube en premier.": "Up there, you see dawn first.",
	"La mer est juste derrière. Le ciel pâlit.": "The sea is just behind. The sky is paling.",
	"Quelqu'un pose deux tasses sur une table.": "Someone sets two cups on a table.",
	"L'eau calme, comme un deuxième ciel.": "Still water, like a second sky.",
	"Les tunnels. Ne comptez pas les lampes.": "The tunnels. Don't count the lights.",
	"Cette route n'est sur aucune carte.": "This road isn't on any map.",
	"La fille au pouce levé. Chaque nuit, plus loin.": "The girl with her thumb out. Further each night.",
	"Vous êtes ici. Encore. Et encore.": "You are here. Again. And again.",
	"Cette voiture sans phares… c'était la vôtre.": "That car with no lights… it was yours.",
	"Une station vide. Une pompe qui pend.": "An empty station. One pump hanging.",
	"Ce tunnel est trop long. Le temps s'arrête.": "This tunnel is too long. Time stops.",
	"Patrouille devant. Au-dessus de 200, elle chasse.": "Patrol ahead. Over 200, they chase.",
	"Encore une patrouille. Ils écoutent la radio.": "Another patrol. They listen to the radio.",
	"Ils vous cherchent. Trois touches, et c'est fini.": "They're looking for you. Three hits and it's over.",
	"Plus de gyrophares. Respirez.": "No more flashing lights. Breathe.",
	"Fin de leur secteur. La nuit est à vous.": "End of their patch. The night is yours.",
	"Contrôle. Le jour, lui, n'a pas attendu.": "Pulled over. Daylight didn't wait.",
	"On parle de vous à l'antenne : %d km/h.": "They're talking about you on air: %d km/h.",
	"MESSAGE DE LOU REÇU — À LIRE À LA PAUSE": "MESSAGE FROM LOU — READ IT IN PAUSE",
	"MESSAGES DE CETTE NUIT": "TONIGHT'S MESSAGES",
}
