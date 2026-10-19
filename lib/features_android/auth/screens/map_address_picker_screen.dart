import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:pgme/core_android/services/location_service.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';
import 'package:pgme/core_android/widgets/app_dialog.dart';

class MapAddressPickerScreen extends StatefulWidget {
  const MapAddressPickerScreen({super.key});

  @override
  State<MapAddressPickerScreen> createState() => _MapAddressPickerScreenState();
}

class _MapAddressPickerScreenState extends State<MapAddressPickerScreen> {
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();

  final _houseController = TextEditingController();
  final _roadController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();

  bool _isLoadingLocation = true;
  bool _isGeocoding = false;
  Timer? _debounce;

  // Default to center of India
  LatLng _currentCenter = const LatLng(20.5937, 78.9629);
  double _currentZoom = 5.0;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _houseController.dispose();
    _roadController.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final position = await _locationService.getCurrentLocation();
    if (position != null && mounted) {
      setState(() {
        _currentCenter = LatLng(position.latitude, position.longitude);
        _currentZoom = 17.0;
        _isLoadingLocation = false;
      });
      _mapController.move(_currentCenter, _currentZoom);
      _reverseGeocode(_currentCenter);
    } else if (mounted) {
      setState(() => _isLoadingLocation = false);
    }
  }

  void _onMapPositionChanged(MapPosition position) {
    if (position.center != null) {
      _currentCenter = position.center!;
    }
    if (position.zoom != null) {
      _currentZoom = position.zoom!;
    }
  }

  Future<void> _reverseGeocode(LatLng position) async {
    setState(() => _isGeocoding = true);

    final structured = await _locationService.getStructuredAddressFromCoordinates(
      position.latitude,
      position.longitude,
    );

    if (structured != null && mounted) {
      setState(() {
        _houseController.text = structured['houseNumber'] ?? '';
        _roadController.text = structured['road'] ?? '';
        _landmarkController.text = structured['suburb'] ?? '';
        _cityController.text = structured['city'] ?? '';
        _stateController.text = structured['state'] ?? '';
        _pincodeController.text = structured['postcode'] ?? '';
        _isGeocoding = false;
      });
    } else if (mounted) {
      setState(() => _isGeocoding = false);
    }
  }

  void _onRecenterTap() async {
    final position = await _locationService.getCurrentLocation();
    if (position != null && mounted) {
      final newCenter = LatLng(position.latitude, position.longitude);
      _mapController.move(newCenter, 17.0);
    }
  }

  String _buildCombinedAddress() {
    final parts = <String>[
      _houseController.text.trim(),
      _roadController.text.trim(),
      _landmarkController.text.trim(),
      _cityController.text.trim(),
      _stateController.text.trim(),
      _pincodeController.text.trim(),
    ].where((s) => s.isNotEmpty).toList();
    return parts.join(', ');
  }

  void _onConfirm() {
    final address = _buildCombinedAddress();
    if (address.isEmpty) {
      showAppDialog(context, message: 'Please select a location on the map');
      return;
    }
    context.pop(address);
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: _isLoadingLocation
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: Color(0xFF0000C8),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Getting your location...',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Color(0xFF78828A),
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                // Map
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentCenter,
                    initialZoom: _currentZoom,
                    onPositionChanged: (position, hasGesture) {
                      _onMapPositionChanged(position);
                      if (hasGesture) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 600), () {
                          _reverseGeocode(_currentCenter);
                        });
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.pgme.app',
                    ),
                  ],
                ),

                // Center pin
                Positioned(
                  top: (screenHeight * 0.45) - (isTablet ? 48 : 40),
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: isTablet ? 48 : 40,
                          color: const Color(0xFFE53935),
                        ),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Geocoding indicator
                if (_isGeocoding)
                  Positioned(
                    top: (screenHeight * 0.45) + (isTablet ? 16 : 12),
                    left: 0,
                    right: 0,
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF0000C8),
                        ),
                      ),
                    ),
                  ),

                // Top bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 8,
                      right: 16,
                      bottom: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.95),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: Icon(
                            Icons.arrow_back,
                            size: isTablet ? 28 : 24,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Pick your location',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 20 : 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Recenter button
                Positioned(
                  bottom: (screenHeight * 0.42) + 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    onPressed: _onRecenterTap,
                    backgroundColor: Colors.white,
                    child: const Icon(
                      Icons.my_location,
                      color: Color(0xFF0000C8),
                    ),
                  ),
                ),

                // Bottom sheet with address fields
                DraggableScrollableSheet(
                  initialChildSize: 0.40,
                  minChildSize: 0.15,
                  maxChildSize: 0.75,
                  builder: (context, scrollController) {
                    return Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, -2),
                          ),
                        ],
                      ),
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 28 : 20,
                          vertical: 12,
                        ),
                        children: [
                          // Drag handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),

                          Text(
                            'Address Details',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 18 : 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Move the map to adjust pin location',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 13 : 11,
                              color: const Color(0xFF78828A),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Address fields
                          _buildField('House / Flat No.', _houseController, isTablet),
                          _buildField('Road / Street', _roadController, isTablet),
                          _buildField('Landmark / Area', _landmarkController, isTablet),
                          _buildField('City', _cityController, isTablet),
                          Row(
                            children: [
                              Expanded(
                                child: _buildField(
                                    'State', _stateController, isTablet),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildField(
                                    'Pincode', _pincodeController, isTablet,
                                    keyboardType: TextInputType.number),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Confirm button
                          SizedBox(
                            width: double.infinity,
                            height: isTablet ? 52 : 46,
                            child: ElevatedButton(
                              onPressed: _onConfirm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0000C8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      isTablet ? 16 : 12),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                'Confirm Location',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isTablet ? 16 : 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                              height:
                                  MediaQuery.of(context).padding.bottom + 8),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    bool isTablet, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: isTablet ? 15 : 13,
          color: Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: isTablet ? 14 : 12,
            color: const Color(0xFF78828A),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: isTablet ? 16 : 12,
            vertical: isTablet ? 14 : 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
            borderSide: const BorderSide(
                color: Color(0xFF0000C8), width: 1.5),
          ),
        ),
      ),
    );
  }
}
