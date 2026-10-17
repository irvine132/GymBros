# Premier APK Android de test — Slice A

Artefact local durable hors Git : `/srv/hermes-dev/toolchains/gym-bro/artifacts/gym-bro-slice-a-0.1.0+1-debug.apk`. SHA-256 : `1d72f5bad3bcf3b70525d49da0a7b6d8f033f073ad258d77e3b697f40a0da18b` ; taille : 154630482 octets. Cette version est **debug**, non destinée au store ni à la production ; ne pas l'installer sur un appareil contenant des données personnelles. Le build est effectivement terminé (`✓ Built build/app/outputs/flutter-apk/app-debug.apk`) et la copie a été comparée par SHA-256. La clé debug Android locale est hors Git (`~/.android/debug.keystore`, mode 0600) ; ne pas la diffuser.

Identité : `dev.gymbro.prototype` ; label `Gym Bro (test)` ; versionName `0.1.0`, versionCode `1` (augmenter `--build-number` à chaque nouvel APK installable). Android min SDK 24, target/compile SDK 36 ; permission INTERNET et permission interne non exportée générée par AndroidX. Signature APK v2 valide, certificat debug SHA-256 `d4f92da861ae3835a41e7f776a1dc309795976628fea16e666df95c70f5431c8`. HTTP en clair permis seulement dans le manifest *debug* ; la release n'est pas validée. Aucun appareil/émulateur connecté à `adb devices -l` : l'installation et le parcours Android **ne sont pas vérifiés**. Le parcours Flutter web et les contrôles API antérieurs ne prouvent pas le lancement Android.

## Reproduire avec les outils Gym Bro locaux

Dans `mobile/` (outils déjà installés, SDK Android dédié contenant platform 36/build-tools 36/NDK 28.2) :

    export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
    export ANDROID_HOME=/srv/hermes-dev/toolchains/gym-bro/android-sdk
    export ANDROID_SDK_ROOT="$ANDROID_HOME"
    export GRADLE_USER_HOME=/srv/hermes-dev/toolchains/gym-bro/gradle-cache
    export PUB_CACHE=/srv/hermes-dev/toolchains/gym-bro/pub-cache
    /srv/hermes-dev/toolchains/gym-bro/flutter/bin/flutter build apk --debug --build-name=0.1.0 --build-number=1 --dart-define=API_BASE=http://127.0.0.1:18081/api/v1
    "$ANDROID_HOME/build-tools/36.0.0/aapt" dump badging build/app/outputs/flutter-apk/app-debug.apk
    "$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose --print-certs build/app/outputs/flutter-apk/app-debug.apk
    sha256sum build/app/outputs/flutter-apk/app-debug.apk

`mobile/android/local.properties` est local/ignoré par Git et doit pointer `sdk.dir` vers le SDK Gym Bro, pas vers le SDK partagé d'un autre projet. La mémoire Gradle est bornée dans `gradle.properties`. Le build observé a requis ~3,8 Go additionnels jusqu'à la copie de l'APK ; contrôler `df -h` avant de le rejouer. Ne pas purger les caches d'autres projets.

## Accès API pour ce binaire

`API_BASE` est un paramètre de compilation Flutter, ici `http://127.0.0.1:18081/api/v1`. Ce `127.0.0.1` désigne **le téléphone**, pas le serveur : ce binaire est utilisable seulement avec un appareil connecté à l'hôte qui exécute l'API et le tunnel USB suivant, maintenu pendant les essais :

    adb devices -l
    adb reverse tcp:18081 tcp:18081
    adb install -r /srv/hermes-dev/toolchains/gym-bro/artifacts/gym-bro-slice-a-0.1.0+1-debug.apk

Vérifier d'abord `curl -i http://127.0.0.1:18081/api/v1/me` sur l'hôte (401 attendu sans jeton) ; jouer ensuite connexion → feed → détail sur l'appareil. Ces commandes `adb reverse/install` sont une procédure, **non exécutées** ici faute d'appareil. Pour tester sur un téléphone non relié, choisir explicitement un endpoint de test privé/VPN joignable et reconstruire avec `--dart-define=API_BASE=https://<hôte-privé>/api/v1` ; ne pas publier l'API ni embarquer d'identifiants. Une URL privée n'a pas été fournie et aucun accès réseau téléphonique autonome n'est revendiqué. Ne pas utiliser une URL HTTP distante en release : la politique Android y bloque le cleartext. Aucun secret n'est requis à la compilation.
