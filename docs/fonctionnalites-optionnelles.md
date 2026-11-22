# openzclick : fonctionnalités non obligatoires, déjà présentes

Inventaire fait sur le code, pas sur le README (commit `badabd4`).
Quatre onglets : Start, Gears, Controllers, Network.

## Le socle indispensable (à ne pas toucher)

1. Démarrer le pont, sa découverte mDNS et son serveur TCP.
2. Connecter le pod en Bluetooth (scan, appairage, session chiffrée).
3. Monter et descendre les vitesses avec les boutons.
4. Le profil de transmission (12 vitesses route, 8 plat, 24 montagne).

Tout ce qui suit vient **en plus** de ça.

## A. Déjà replié, donc presque invisible (coût ≈ 0)

| Fonctionnalité | Où | Verdict |
|---|---|---|
| Banc d'essai du protocole | Network, replié (« Protocol test bench ») | Outil de développeur : à sortir du build public |
| Détail « Gear set and riding mode » | Gears, replié | Ok replié |
| « Adjust the keys » | Network, replié | Ok replié |
| Recommandation « Quietest : … » dans le choix du pignon | Gears | `recommendParkedGear` propose automatiquement le pignon le plus silencieux, optionnel |

## B. Réglages optionnels exposés à l'écran (candidats au retrait)

| Fonctionnalité | Où | Pourquoi c'est en trop |
|---|---|---|
| Mode ERG / SIM + cible de puissance (±5 W) | Gears, replié | MyWhoosh fait son propre ERG. Deux endroits pour régler la même chose. Badge « ERG 240 W » en permanence dans l'écran |
| Changer de plateau (grand / petit) | Gears, bouton | Réglage de matériel fait une fois, présenté comme un bouton de ride |
| Vitesses par appui (×1 ×2 ×3) | Network | Réglage fin, jamais demandé par un débutant |
| Choix du profil clavier (MyWhoosh / Rouvy / Biketerra / autre) | Network | Utile seulement hors protocole |
| « Type into this window only » (fragment de titre de fenêtre) | Network | Réglage de puissance pour utilisateurs avancés |

## C. Injections alternatives (trois voies pour le même résultat)

| Fonctionnalité | Plateforme | Verdict |
|---|---|---|
| Injection de touches (X11 / SendInput) | Linux, Windows | À garder, mais caché derrière « l'app ne parle pas le protocole » |
| Injection de taps par service d'accessibilité | Android | Idem |
| Positions de tap réglables au doigt (slider %) | Android | Réglage très avancé, présent dans l'écran principal |

## D. Diagnostics et console

| Fonctionnalité | Où | Verdict |
|---|---|---|
| « Copy device report » (GATT, trames) | Controllers | Outil de support, pas de rider |
| Last buttons / pastilles de couleurs des boutons | Controllers | Documente le pod, ne sert pas à rouler |
| Pastille de batterie | Controllers | Correctif utile, mais c'est du diagnostic |
| Console navigateur + QR code + code à 4 chiffres | Network | Une deuxième façon de piloter le pont |

## E. Onboarding et guidage

| Fonctionnalité | Où |
|---|---|
| Guide de premier démarrage (4 écrans, « Skip ») | Au lancement |
| « Show the first-start guide again » | Start |
| Carte « Not using MyWhoosh ? » (6 autres applis) | Start |
| « One tap ride » (bouton unique qui scanne, connecte, démarre) | Start, version web |
| Voyant Ready / Not ready cliquable qui renvoie vers l'onglet à corriger | Barre du haut, partout |

## F. Le cas le plus discutable

- **Directions (gauche / droite, double appui)** : le README l'annonce comme une
  fonctionnalité de premier plan (« Intersection choices »), mais dans `core`,
  les bindings par défaut ont `doubleTap: Action.none` depuis le correctif
  « deux vitesses rapidement = un virage ». Reste un bouton « Send a direction »
  dans Network. Soit on l'assume, soit on l'enlève : aujourd'hui l'un et l'autre.

## Proposition de simplification, par ordre de gain

1. Controllers reste ce qu'il est (connexion + diagnostic), mais perd les pastilles de couleurs.
2. Network : ne garder que « Publier sur le réseau » et la console, envoyer injection / clavier / positions / vitesses-par-appui dans un seul écran « Avancé ».
3. Gears : le mode ERG et le plateau disparaissent, le pont ne publie que des vitesses.
4. Retirer le banc d'essai du build public.
5. Trancher sur les directions.
