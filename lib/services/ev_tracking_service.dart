import 'package:latlong2/latlong.dart';

class CampusStop {
  const CampusStop({
    required this.name,
    required this.blockPosition,
    required this.pickupPosition,
  });

  final String name;
  final LatLng blockPosition;
  final LatLng pickupPosition;
}

class EvTrackingService {
  static const double facultyEligibilityRadiusMeters = 100.0;

  static const double evTriggerRadiusMeters = 35.0;

  static const LatLng adbPickup = LatLng(12.840951820403735, 80.15396413016246);

  static const LatLng ab2Pickup = LatLng(12.843317366244131, 80.15638997128873);

  static const LatLng ab4Pickup = LatLng(12.843489770901007, 80.1557089418644);

  static const LatLng ab3Pickup = LatLng(12.844324726682181, 80.15516153162771);

  static const LatLng ab1Pickup = LatLng(12.844308777465374, 80.15324914094315);

  static const LatLng ab1Block = LatLng(12.84391293192312, 80.15342317676296);

  static const LatLng ab2Block = LatLng(12.843120555928554, 80.15645139066287);

  static const LatLng ab3Block = LatLng(12.844043686792524, 80.15474014135296);

  static const LatLng ab4Block = LatLng(12.843127357629559, 80.1554401593973);

  static const LatLng adbBlock = LatLng(12.840719876775859, 80.15393816088053);

  static const List<CampusStop> campusStops = [
    CampusStop(name: 'ADB', blockPosition: adbBlock, pickupPosition: adbPickup),
    CampusStop(name: 'AB2', blockPosition: ab2Block, pickupPosition: ab2Pickup),
    CampusStop(name: 'AB4', blockPosition: ab4Block, pickupPosition: ab4Pickup),
    CampusStop(name: 'AB3', blockPosition: ab3Block, pickupPosition: ab3Pickup),
    CampusStop(name: 'AB1', blockPosition: ab1Block, pickupPosition: ab1Pickup),
  ];

  static const List<LatLng> pickupPoints = [
    adbPickup,
    ab2Pickup,
    ab4Pickup,
    ab3Pickup,
    ab1Pickup,
  ];

  static const List<String> pickupNames = ['ADB', 'AB2', 'AB4', 'AB3', 'AB1'];

  static const List<LatLng> buggyRoad = [
    // Line 2
    LatLng(12.8441727, 80.1553903),
    LatLng(12.8445047, 80.1548582),
    LatLng(12.8445298, 80.1548324),
    LatLng(12.8445437, 80.1547866),
    LatLng(12.8445772, 80.1545091),
    LatLng(12.8445883, 80.1543117),
    LatLng(12.8445828, 80.1542631),
    LatLng(12.8445102, 80.1537367),
    LatLng(12.8444935, 80.1536422),
    LatLng(12.8444684, 80.1535249),
    LatLng(12.8444377, 80.1534191),
    LatLng(12.8443903, 80.1533132),
    LatLng(12.8443178, 80.1532045),
    LatLng(12.8442592, 80.1531503),
    LatLng(12.8440807, 80.1530044),
    LatLng(12.8439077, 80.1528814),
    LatLng(12.8438268, 80.1528556),
    LatLng(12.8433582, 80.1527669),
    LatLng(12.8431406, 80.152724),
    LatLng(12.8430765, 80.1527212),
    LatLng(12.8429816, 80.1527069),
    LatLng(12.8429119, 80.1527011),
    LatLng(12.8428171, 80.1527011),
    LatLng(12.8427166, 80.1527097),
    LatLng(12.8425855, 80.1527298),
    LatLng(12.8424862, 80.1527584),
    LatLng(12.8423941, 80.1527984),
    LatLng(12.842302, 80.1528499),
    LatLng(12.8422044, 80.1529357),
    LatLng(12.842108, 80.1530616),
    LatLng(12.8420271, 80.1531932),
    LatLng(12.8419556, 80.1533191),
    LatLng(12.8419082, 80.153405),
    LatLng(12.8418357, 80.1534793),
    LatLng(12.841766, 80.1535451),
    LatLng(12.8417213, 80.153671),
    LatLng(12.8416627, 80.153671),
    LatLng(12.8415763, 80.1536367),
    LatLng(12.8414284, 80.1536367),
    LatLng(12.8413113, 80.1536167),
    LatLng(12.8411823, 80.1535881),
    LatLng(12.8410679, 80.1535394),
    LatLng(12.8409507, 80.1534936),
    LatLng(12.8409563, 80.1535194),
    LatLng(12.8409368, 80.1535881),
    LatLng(12.8408949, 80.1538026),
    LatLng(12.840867, 80.1539629),
    LatLng(12.8408252, 80.1541517),
    LatLng(12.8407945, 80.1542661),
    LatLng(12.8407583, 80.1543577),
    LatLng(12.8407164, 80.1544721),
    LatLng(12.8406857, 80.1545608),
    LatLng(12.8407834, 80.1545351),
    LatLng(12.8414026, 80.1543777),
    LatLng(12.8414033, 80.1544453),
    LatLng(12.8413245, 80.1546438),
    LatLng(12.8412799, 80.1547926),
    LatLng(12.8412855, 80.1549442),
    LatLng(12.8413106, 80.1550844),
    LatLng(12.8413831, 80.1552417),
    LatLng(12.8416397, 80.1556537),
    LatLng(12.8417067, 80.1557539),
    LatLng(12.8419159, 80.1560124),
    LatLng(12.8419996, 80.1561126),
    LatLng(12.8420442, 80.1562499),
    LatLng(12.8421446, 80.1563643),
    LatLng(12.8422618, 80.156475),
    LatLng(12.8423734, 80.1565494),
    LatLng(12.8425156, 80.1566209),
    LatLng(12.8427424, 80.1567364),

    // Line 3
    LatLng(12.8429351, 80.1568321),
    LatLng(12.8430885, 80.1569036),
    LatLng(12.8432308, 80.1569608),
    LatLng(12.8433061, 80.156998),
    LatLng(12.8433451, 80.1569465),
    LatLng(12.843561, 80.1565117),
    LatLng(12.8434079, 80.1564433),
    LatLng(12.8432634, 80.1563947),
    LatLng(12.8434971, 80.1559748),
    LatLng(12.8435185, 80.1559969),
    LatLng(12.8433215, 80.1563542),
    LatLng(12.8434587, 80.156436),
    LatLng(12.8435985, 80.1565044),
    LatLng(12.8437932, 80.1562899),
    LatLng(12.8438971, 80.1561759),
    LatLng(12.8439359, 80.1561283),
    LatLng(12.8439644, 80.1560646),
    LatLng(12.8440271, 80.1558654),
    LatLng(12.8440768, 80.1556448),
    LatLng(12.8441727, 80.1553903),
  ];

  final Distance _distance = const Distance();

  double distanceBetween(LatLng first, LatLng second) {
    return _distance.as(LengthUnit.Meter, first, second);
  }

  CampusStop? findFacultyBlock(LatLng facultyPosition) {
    for (final stop in campusStops) {
      final distanceToBlock = distanceBetween(
        facultyPosition,
        stop.blockPosition,
      );

      final distanceToPickup = distanceBetween(
        facultyPosition,
        stop.pickupPosition,
      );

      if (distanceToBlock <= facultyEligibilityRadiusMeters ||
          distanceToPickup <= facultyEligibilityRadiusMeters) {
        return stop;
      }
    }

    return null;
  }

  bool isEvNearStop(LatLng evPosition, CampusStop stop) {
    final distanceToBlock = distanceBetween(evPosition, stop.blockPosition);

    final distanceToPickup = distanceBetween(evPosition, stop.pickupPosition);

    return distanceToBlock <= evTriggerRadiusMeters ||
        distanceToPickup <= evTriggerRadiusMeters;
  }
}
