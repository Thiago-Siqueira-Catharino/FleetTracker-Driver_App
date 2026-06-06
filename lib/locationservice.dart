import 'package:geolocator/geolocator.dart';

class LocationService {

  Future<Position> determinarPosicao() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error("Serviço de localização desativado.");
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied){
      permission == await Geolocator.requestPermission();

      if (permission == LocationPermission.denied){
        return Future.error("Permissão de localização negada");
      }
    }

    if (permission == LocationPermission.deniedForever){
      return Future.error("As permissões de localização foram negadas permanentemente. Aceite-as para garantir o funcionamento do app");
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)
    );
  }
}
