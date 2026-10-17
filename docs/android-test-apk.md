# Premier APK Android de test — Slice A

Artefact de diffusion hors Git : `/srv/hermes-dev/toolchains/gym-bro/artifacts/gym-bro-slice-a-0.1.0+2001-arm64-test.apk`. SHA-256 : `b540e76431f62c2c9d9eaebb5b378a5ae2377ca881e866d39cc4d8a054c4b505` ; taille : 18398954 octets. APK Flutter **optimisé release, arm64-v8a uniquement, signé avec la clé debug de test**, non destiné au store ni à la production ; ne pas l'installer sur un appareil contenant des données personnelles. Le build `--release --split-per-abi` a terminé (arm64-v8a 18,4 Mo ; armeabi-v7a 15,7 Mo ; x86_64 19,8 Mo), et source/copie ont des SHA identiques. L'APK debug universel initial reste conservé au même emplacement (`gym-bro-slice-a-0.1.0+1-debug.apk`, SHA-256 `1d72f5bad3bcf3b70525d49da0a7b6d8f033f073ad258d77e3b697f40a0da18b`, 154630482 octets) mais Discord l'a refusé avec HTTP 413 : **son envoi a échoué**, même si un message texte a été publié. La clé debug Android locale est hors Git (`~/.android/debug.keystore`, mode 0600) ; ne pas la diffuser.

Identité : `dev.gymbro.prototype` ; label `Gym Bro (test)` ; versionName `0.1.0`, versionCode **2001** dans l'APK arm64 (Flutter ajoute le préfixe ABI à `--build-number=1`; augmenter le numéro de build au prochain incrément). Android min SDK 24, target/compile SDK 36 ; permission INTERNET et permission interne non exportée générée par AndroidX. Signature APK v2 valide, certificat debug SHA-256 `d4f92da861ae3835a41e7f776a1dc309795976628fea16e666df95c70f5431c8`. Le manifest *release de test* référence `@xml/test_network_security_config` : base cleartext refusé, exception uniquement pour `127.0.0.1` (tunnel adb reverse). Manifest debug distinct autorise HTTP pour développement. Ce n'est ni un durcissement sécurité bêta ni une release commerciale. Aucun appareil/émulateur connecté à `adb devices -l` : l'installation et le parcours Android **ne sont pas vérifiés**. Le parcours Flutter web et les contrôles API antérieurs ne prouvent pas le lancement Android.

## Reproduire avec les outils Gym Bro locaux

Dans `mobile/` (outils déjà installés, SDK Android dédié contenant platform 36/build-tools 36/NDK 28.2) :

    export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
    export ANDROID_HOME=/srv/hermes-dev/toolchains/gym-bro/android-sdk
    export ANDROID_SDK_ROOT="$ANDROID_HOME"
    export GRADLE_USER_HOME=/srv/hermes-dev/toolchains/gym-bro/gradle-cache
    export PUB_CACHE=/srv/hermes-dev/toolchains/gym-bro/pub-cache
    /srv/hermes-dev/toolchains/gym-bro/flutter/bin/flutter build apk --release --split-per-abi --build-name=0.1.0 --build-number=1 --dart-define=API_BASE=http://127.0.0.1:18081/api/v1
    "$ANDROID_HOME/build-tools/36.0.0/aapt" dump badging build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
    "$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
    sha256sum build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

`mobile/android/local.properties` est local/ignoré par Git et doit pointer `sdk.dir` vers le SDK Gym Bro, pas vers le SDK partagé d'un autre projet. La mémoire Gradle est bornée dans `gradle.properties`. Les builds debug puis optimisé ont laissé <1 Go libre ; **ne pas relancer sans marge disque**. Ne pas purger les caches d'autres projets.

## Accès API pour ce binaire

`API_BASE` est un paramètre de compilation Flutter, ici `http://127.0.0.1:18081/api/v1`. Ce `127.0.0.1` désigne **le téléphone**, pas le serveur : ce binaire est utilisable seulement avec un appareil connecté à l'hôte qui exécute l'API et le tunnel USB suivant, maintenu pendant les essais :

    adb devices -l
    adb reverse tcp:18081 tcp:18081
    adb install -r /srv/hermes-dev/toolchains/gym-bro/artifacts/gym-bro-slice-a-0.1.0+2001-arm64-test.apk

Vérifier d'abord `curl -i http://127.0.0.1:18081/api/v1/me` sur l'hôte (401 attendu sans jeton) ; jouer ensuite connexion → feed → détail sur l'appareil. Ces commandes `adb reverse/install` sont une procédure, **non exécutées** ici faute d'appareil. Pour tester sur un téléphone non relié, choisir explicitement un endpoint de test privé/VPN joignable et reconstruire avec `--dart-define=API_BASE=https://<hôte-privé>/api/v1` ; ne pas publier l'API ni embarquer d'identifiants. Une URL privée n'a pas été fournie et aucun accès réseau téléphonique autonome n'est revendiqué. Ne pas utiliser une URL HTTP distante en release : la politique Android y bloque le cleartext. Aucun secret n'est requis à la compilation.
