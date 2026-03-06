import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/models/live_session_model.dart';
import 'package:pgme/core/models/package_model.dart';
import 'package:pgme/core/models/package_type_model.dart';
import 'package:pgme/core/models/video_model.dart';
import 'package:pgme/core/models/faculty_model.dart';
import 'package:pgme/core/models/subject_selection_model.dart';
import 'package:pgme/core/models/series_model.dart';
import 'package:pgme/core/models/module_model.dart';
import 'package:pgme/core/models/series_document_model.dart';
import 'package:pgme/core/models/library_item_model.dart';
import 'package:pgme/core/models/gateway_models.dart';
import 'package:pgme/core/models/banner_model.dart';
import 'package:pgme/core/models/home_section_model.dart';
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/core/services/gateway_service.dart';

class DashboardService {
  final ApiService _apiService = ApiService();
  final GatewayService _gatewayService = GatewayService();

  // Cache for faculty (1 hour TTL)
  DateTime? _lastFacultyFetch;
  List<FacultyModel>? _cachedFaculty;

  // Cache for packages (1 hour TTL)
  DateTime? _lastPackagesFetch;
  List<PackageModel>? _cachedPackages;
  String? _cachedPackagesSubjectId;
  String? _cachedPackagesType;

  /// Get next upcoming live session
  /// Returns null if no upcoming session found
  Future<LiveSessionModel?> getNextUpcomingSession({String? subjectId}) async {
    try {
      debugPrint('=== DashboardService: Getting next upcoming session ===');

      final queryParams = <String, dynamic>{};
      if (subjectId != null) {
        queryParams['subject_id'] = subjectId;
      }

      final response = await _apiService.dio.get(
        ApiConstants.nextUpcomingSession,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final sessionData = response.data['data']['session'];

        // If session is null, no upcoming session
        if (sessionData == null) {
          debugPrint('✓ No upcoming session');
          return null;
        }

        final session = LiveSessionModel.fromJson(sessionData as Map<String, dynamic>);
        debugPrint('✓ Next upcoming session retrieved: ${session.title}');
        return session;
      }

      throw Exception('Failed to load upcoming session');
    } on DioException catch (e) {
      debugPrint('✗ Get upcoming session error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get list of live sessions with filters
  Future<List<LiveSessionModel>> getLiveSessions({
    String? status,
    String? subjectId,
    int limit = 10,
    bool upcomingOnly = false,
  }) async {
    try {
      debugPrint('=== DashboardService: Getting live sessions ===');

      final queryParams = <String, dynamic>{
        'limit': limit,
      };

      if (status != null) queryParams['status'] = status;
      if (subjectId != null) queryParams['subject_id'] = subjectId;
      if (upcomingOnly) queryParams['upcoming_only'] = true;

      final response = await _apiService.dio.get(
        ApiConstants.liveSessions,
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final sessionsData = response.data['data']['sessions'] as List;
        final sessions = sessionsData
            .map((json) => LiveSessionModel.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('✓ ${sessions.length} live sessions retrieved');
        return sessions;
      }

      throw Exception('Failed to load live sessions');
    } on DioException catch (e) {
      debugPrint('✗ Get live sessions error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get live sessions by series ID (for practical packages)
  Future<List<LiveSessionModel>> getLiveSessionsBySeries(String seriesId) async {
    try {
      debugPrint('=== DashboardService: Getting live sessions for series $seriesId ===');

      final queryParams = <String, dynamic>{
        'series_id': seriesId,
        'limit': 50,
      };

      final response = await _apiService.dio.get(
        ApiConstants.liveSessions,
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final sessionsData = response.data['data']['sessions'] as List;
        final sessions = sessionsData
            .map((json) => LiveSessionModel.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('✓ ${sessions.length} live sessions retrieved for series');
        return sessions;
      }

      throw Exception('Failed to load live sessions for series');
    } on DioException catch (e) {
      debugPrint('✗ Get live sessions by series error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get live session details by ID
  Future<LiveSessionModel> getSessionDetails(String sessionId) async {
    try {
      debugPrint('=== DashboardService: Getting session details ===');

      final response = await _apiService.dio.get(
        ApiConstants.liveSessionDetails(sessionId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final sessionData = response.data['data']['session'] as Map<String, dynamic>;

        // Flatten nested faculty and subject objects to match LiveSessionModel
        final flattenedData = <String, dynamic>{
          ...sessionData,
        };

        // Flatten faculty object
        if (sessionData['faculty'] != null) {
          final faculty = sessionData['faculty'] as Map<String, dynamic>;
          flattenedData['faculty_id'] = faculty['faculty_id'];
          flattenedData['faculty_name'] = faculty['name'];
          flattenedData['faculty_photo_url'] = faculty['photo_url'];
          flattenedData['faculty_specialization'] = faculty['specialization'];
        }

        // Flatten subject object
        if (sessionData['subject'] != null) {
          final subject = sessionData['subject'] as Map<String, dynamic>;
          flattenedData['subject_id'] = subject['subject_id'];
          flattenedData['subject_name'] = subject['name'];
        }

        // Debug: Log raw API data for pricing
        debugPrint('=== Raw API Response ===');
        debugPrint('is_free from API: ${flattenedData['is_free']}');
        debugPrint('price from API: ${flattenedData['price']}');

        final session = LiveSessionModel.fromJson(flattenedData);

        debugPrint('✓ Session details retrieved: ${session.title}');
        debugPrint('Parsed isFree: ${session.isFree}, price: ${session.price}');
        return session;
      }

      throw Exception('Failed to load session details');
    } on DioException catch (e) {
      debugPrint('✗ Get session details error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get active banners for carousel
  Future<List<BannerModel>> getBanners() async {
    try {
      debugPrint('=== DashboardService: Getting banners ===');

      final response = await _apiService.dio.get(
        ApiConstants.banners,
        queryParameters: {'is_active': true},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final List<dynamic> bannersData = response.data['data']['banners'] ?? [];

        final banners = bannersData
            .map((json) => BannerModel.fromJson(json as Map<String, dynamic>))
            .toList();

        // Sort by display order
        banners.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

        debugPrint('✓ Banners retrieved: ${banners.length}');
        return banners;
      }

      return [];
    } on DioException catch (e) {
      debugPrint('✗ Get banners error: $e');
      return []; // Return empty list on error to not break UI
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      return [];
    }
  }

  /// Get dynamic home sections (public endpoint, no auth required)
  Future<List<HomeSectionModel>> getHomeSections() async {
    try {
      debugPrint('=== DashboardService: Getting home sections ===');

      final response = await _apiService.dio.get(
        ApiConstants.homeSections,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final sectionsData = response.data['data']['sections'] as List;
        final sections = sectionsData
            .map((json) =>
                HomeSectionModel.fromJson(json as Map<String, dynamic>))
            .toList();

        sections.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

        debugPrint('✓ ${sections.length} home sections retrieved');
        return sections;
      }

      return [];
    } on DioException catch (e) {
      debugPrint('✗ Get home sections error: $e');
      return [];
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      return [];
    }
  }

  /// Get user's subject selections
  /// Use isPrimary: true to get only the primary subject
  Future<List<SubjectSelectionModel>> getSubjectSelections({bool? isPrimary}) async {
    try {
      debugPrint('=== DashboardService: Getting subject selections ===');

      final queryParams = <String, dynamic>{};
      if (isPrimary != null) {
        queryParams['is_primary'] = isPrimary.toString();
      }

      final response = await _apiService.dio.get(
        ApiConstants.subjectSelections,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final selectionsData = response.data['data']['selections'] as List;
        final selections = selectionsData
            .map((json) => SubjectSelectionModel.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('✓ ${selections.length} subject selections retrieved');
        return selections;
      }

      throw Exception('Failed to load subject selections');
    } on DioException catch (e) {
      debugPrint('✗ Get subject selections error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get available packages
  /// Use forceRefresh to bypass cache
  Future<List<PackageModel>> getPackages({
    String? subjectId,
    String? packageType,
    bool forceRefresh = false,
  }) async {
    try {
      debugPrint('=== DashboardService: Getting packages ===');

      // Check cache validity (1 hour TTL)
      if (!forceRefresh &&
          _cachedPackages != null &&
          _lastPackagesFetch != null &&
          _cachedPackagesSubjectId == subjectId &&
          _cachedPackagesType == packageType &&
          DateTime.now().difference(_lastPackagesFetch!) < const Duration(hours: 1)) {
        debugPrint('✓ Returning cached packages (${_cachedPackages!.length} items)');
        return _cachedPackages!;
      }

      final queryParams = <String, dynamic>{};
      if (subjectId != null) queryParams['subject_id'] = subjectId;
      if (packageType != null) queryParams['package_type'] = packageType;

      final response = await _apiService.dio.get(
        ApiConstants.packages,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        debugPrint('Raw packages response: ${response.data}');
        final packagesData = response.data['data']['packages'] as List;
        debugPrint('Packages data list: $packagesData');
        final packages = packagesData
            .where((json) => json != null)
            .map((json) => PackageModel.fromJson(json as Map<String, dynamic>))
            .toList();

        // Sort by display_order
        packages.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

        // Update cache
        _cachedPackages = packages;
        _lastPackagesFetch = DateTime.now();
        _cachedPackagesSubjectId = subjectId;
        _cachedPackagesType = packageType;

        debugPrint('✓ ${packages.length} packages retrieved and cached');
        return packages;
      }

      throw Exception('Failed to load packages');
    } on DioException catch (e) {
      debugPrint('✗ Get packages error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get package details by ID (includes trailer video info)
  Future<PackageModel?> getPackageDetails(String packageId) async {
    try {
      debugPrint('=== DashboardService: Getting package details ===');
      debugPrint('Package ID: $packageId');

      final response = await _apiService.dio.get(
        '${ApiConstants.packages}/$packageId',
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final packageData = response.data['data'] as Map<String, dynamic>;
        final pkg = PackageModel.fromJson(packageData);
        debugPrint('✓ Package details retrieved: ${pkg.name}');
        return pkg;
      }

      return null;
    } on DioException catch (e) {
      debugPrint('✗ Get package details error: $e');
      return null; // Non-fatal - screen can still work without package details
    } catch (e) {
      debugPrint('✗ Unexpected error getting package details: $e');
      return null;
    }
  }

  /// Get all package types
  Future<List<PackageTypeModel>> getPackageTypes() async {
    try {
      debugPrint('=== DashboardService: Getting package types ===');

      final response = await _apiService.dio.get(
        ApiConstants.packageTypes,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final packageTypesData = response.data['data']['packageTypes'] as List;
        final packageTypes = packageTypesData
            .map((json) => PackageTypeModel.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('✓ ${packageTypes.length} package types retrieved');
        return packageTypes;
      }

      throw Exception('Failed to load package types');
    } on DioException catch (e) {
      debugPrint('✗ Get package types error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get user's last watched videos
  Future<List<VideoModel>> getLastWatchedVideos({int limit = 1, String? subjectId}) async {
    try {
      debugPrint('=== DashboardService: Getting last watched videos ===');

      final queryParams = <String, dynamic>{'limit': limit};
      if (subjectId != null) {
        queryParams['subject_id'] = subjectId;
      }

      final response = await _apiService.dio.get(
        ApiConstants.lastWatched,
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final videosData = response.data['data']['videos'] as List;
        final videos = videosData
            .map((json) => VideoModel.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('✓ ${videos.length} last watched videos retrieved');
        return videos;
      }

      throw Exception('Failed to load last watched videos');
    } on DioException catch (e) {
      debugPrint('✗ Get last watched videos error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get faculty list
  /// Use forceRefresh to bypass cache
  Future<List<FacultyModel>> getFaculty({
    int limit = 10,
    String? specialization,
    bool forceRefresh = false,
  }) async {
    try {
      debugPrint('=== DashboardService: Getting faculty list ===');

      // Check cache validity (1 hour TTL)
      if (!forceRefresh &&
          _cachedFaculty != null &&
          _lastFacultyFetch != null &&
          DateTime.now().difference(_lastFacultyFetch!) < const Duration(hours: 1)) {
        debugPrint('✓ Returning cached faculty (${_cachedFaculty!.length} items)');

        // Apply limit to cached data
        if (_cachedFaculty!.length > limit) {
          return _cachedFaculty!.sublist(0, limit);
        }
        return _cachedFaculty!;
      }

      final queryParams = <String, dynamic>{
        'limit': limit,
      };
      if (specialization != null) {
        queryParams['specialization'] = specialization;
      }

      final response = await _apiService.dio.get(
        ApiConstants.faculty,
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final facultyData = response.data['data']['faculty'] as List;
        final faculty = facultyData
            .map((json) => FacultyModel.fromJson(json as Map<String, dynamic>))
            .toList();

        // Update cache
        _cachedFaculty = faculty;
        _lastFacultyFetch = DateTime.now();

        debugPrint('✓ ${faculty.length} faculty members retrieved and cached');
        return faculty;
      }

      throw Exception('Failed to load faculty');
    } on DioException catch (e) {
      debugPrint('✗ Get faculty error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get faculty details by ID
  Future<FacultyModel> getFacultyDetails(String facultyId) async {
    try {
      debugPrint('=== DashboardService: Getting faculty details ===');

      final response = await _apiService.dio.get(
        ApiConstants.facultyDetails(facultyId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final facultyData = response.data['data']['faculty'];
        final faculty = FacultyModel.fromJson(facultyData as Map<String, dynamic>);

        debugPrint('✓ Faculty details retrieved: ${faculty.name}');
        return faculty;
      }

      throw Exception('Failed to load faculty details');
    } on DioException catch (e) {
      debugPrint('✗ Get faculty details error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get series for a specific package
  Future<({List<SeriesModel> series, bool isPurchased})> getPackageSeries(String packageId) async {
    try {
      debugPrint('=== DashboardService: Getting package series ===');
      debugPrint('Package ID: $packageId');

      final response = await _apiService.dio.get(
        ApiConstants.packageSeries(packageId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        debugPrint('Raw series response: ${response.data}');

        final data = response.data['data'];
        final isPurchased = data['is_purchased'] == true;
        final seriesData = data['series'] as List;
        debugPrint('Series data list: $seriesData');
        debugPrint('Is purchased: $isPurchased');

        final series = seriesData
            .map((json) => SeriesModel.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('√ ${series.length} series retrieved');
        return (series: series, isPurchased: isPurchased);
      } else {
        debugPrint('✗ Failed to retrieve series');
        throw Exception('Failed to retrieve series');
      }
    } on DioException catch (e) {
      debugPrint('✗ Get series error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get series details by ID
  Future<SeriesModel> getSeriesDetails(String seriesId) async {
    try {
      debugPrint('=== DashboardService: Getting series details ===');
      debugPrint('Series ID: $seriesId');

      final response = await _apiService.dio.get(
        '/series/$seriesId',
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final seriesData = response.data['data'];
        final series = SeriesModel.fromJson(seriesData as Map<String, dynamic>);

        debugPrint('√ Series details retrieved: ${series.title}');
        return series;
      }

      throw Exception('Failed to load series details');
    } on DioException catch (e) {
      debugPrint('✗ Get series details error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get modules for a specific series
  Future<List<ModuleModel>> getSeriesModules(String seriesId) async {
    try {
      debugPrint('=== DashboardService: Getting series modules ===');
      debugPrint('Series ID: $seriesId');

      final response = await _apiService.dio.get(
        '/series/$seriesId/modules',
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final modulesData = response.data['data']['modules'] as List;
        final modules = modulesData
            .map((json) => ModuleModel.fromJson(json as Map<String, dynamic>))
            .toList();

        // Sort by display_order
        modules.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

        debugPrint('√ ${modules.length} modules retrieved');
        return modules;
      }

      throw Exception('Failed to load series modules');
    } on DioException catch (e) {
      debugPrint('✗ Get series modules error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get documents for a specific series
  Future<List<SeriesDocumentModel>> getSeriesDocuments(String seriesId) async {
    try {
      debugPrint('=== DashboardService: Getting series documents ===');
      debugPrint('Series ID: $seriesId');

      final response = await _apiService.dio.get(
        '/series/$seriesId/documents',
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final documentsData = response.data['data']['documents'] as List;
        final documents = documentsData
            .map((json) => SeriesDocumentModel.fromJson(json as Map<String, dynamic>))
            .toList();

        // Sort by display_order
        documents.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

        debugPrint('√ ${documents.length} documents retrieved');
        return documents;
      }

      throw Exception('Failed to load series documents');
    } on DioException catch (e) {
      debugPrint('✗ Get series documents error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Purchase a package (test purchase - bypasses payment gateway)
  Future<Map<String, dynamic>> purchasePackage(String packageId) async {
    try {
      debugPrint('=== DashboardService: Purchasing package ===');
      debugPrint('Package ID: $packageId');

      final response = await _apiService.dio.post(
        ApiConstants.packageTestPurchase(packageId),
      );

      if (response.statusCode == 201 && response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        debugPrint('✓ Package purchased successfully');
        return data;
      }

      throw Exception(response.data['message'] ?? 'Failed to purchase package');
    } on DioException catch (e) {
      debugPrint('✗ Purchase package error: $e');
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get user's library (notes/documents)
  Future<List<LibraryItemModel>> getUserLibrary({bool? isBookmarked, String? subjectId}) async {
    try {
      debugPrint('=== DashboardService: Getting user library ===');

      final queryParams = <String, dynamic>{};
      if (isBookmarked != null) {
        queryParams['is_bookmarked'] = isBookmarked.toString();
      }
      if (subjectId != null) {
        queryParams['subject_id'] = subjectId;
      }

      final response = await _apiService.dio.get(
        ApiConstants.userLibrary,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final libraryData = response.data['data']['library'] as List;
        final library = libraryData
            .map((json) => LibraryItemModel.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('✓ ${library.length} library items retrieved');
        return library;
      }

      throw Exception('Failed to load library');
    } on DioException catch (e) {
      debugPrint('✗ Get library error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Add document to user's library
  Future<Map<String, dynamic>> addToLibrary(String documentId) async {
    try {
      debugPrint('=== DashboardService: Adding to library ===');

      final response = await _apiService.dio.post(
        ApiConstants.userLibrary,
        data: {'document_id': documentId},
      );

      if (response.statusCode == 201 && response.data['success'] == true) {
        debugPrint('✓ Document added to library');
        return response.data['data'] as Map<String, dynamic>;
      }

      throw Exception(response.data['message'] ?? 'Failed to add to library');
    } on DioException catch (e) {
      debugPrint('✗ Add to library error: $e');
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Toggle bookmark status for a library item
  Future<bool> toggleBookmark(String libraryId, bool isBookmarked) async {
    try {
      final response = await _apiService.dio.put(
        ApiConstants.libraryBookmark(libraryId),
        data: {'is_bookmarked': isBookmarked},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return true;
      }
      return false;
    } on DioException catch (e) {
      debugPrint('Toggle bookmark error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    }
  }

  /// Check if user has any active package purchases
  Future<bool> hasActivePurchases() async {
    try {
      debugPrint('=== DashboardService: Checking active purchases ===');

      final response = await _apiService.dio.get(
        ApiConstants.activeUserRecords,
        queryParameters: {
          'is_active': 'true',
          'payment_status': 'completed',
          'limit': 1,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final purchases = response.data['data']['purchases'] as List;
        final hasActive = purchases.isNotEmpty;
        debugPrint('✓ Active purchases check: $hasActive (${purchases.length} found)');
        return hasActive;
      }

      return false;
    } on DioException catch (e) {
      debugPrint('✗ Check active purchases error: $e');
      return false;
    } catch (e) {
      debugPrint('✗ Unexpected error: $e');
      return false;
    }
  }

  // ============================================================================
  // ZOHO PAYMENTS METHODS (Package Purchases)
  // ============================================================================

  /// Create Zoho payment session for package purchase
  Future<GatewaySession> createPackagePaymentSession(
    String packageId, {
    Map<String, dynamic>? billingAddress,
    int? tierIndex,
  }) async {
    return await _gatewayService.initSession(
      endpoint: ApiConstants.activeInitAccessSession,
      data: {
        'package_id': packageId,
        if (billingAddress != null) 'billing_address': billingAddress,
        if (tierIndex != null) 'tier_index': tierIndex,
      },
    );
  }

  /// Verify Zoho payment for package purchase
  Future<GatewayVerificationResponse> verifyPackagePayment({
    required String paymentSessionId,
    required String paymentId,
    String? signature,
  }) async {
    return await _gatewayService.confirmSession(
      endpoint: ApiConstants.activeConfirmAccess,
      paymentSessionId: paymentSessionId,
      paymentId: paymentId,
      signature: signature,
    );
  }

  /// Calculate upgrade price preview (pro-rata credit)
  Future<Map<String, dynamic>> calculateUpgradePrice(
    String packageId,
    int targetTierIndex,
  ) async {
    try {
      final response = await _apiService.dio.post(
        ApiConstants.activeTierPreview,
        data: {
          'package_id': packageId,
          'target_tier_index': targetTierIndex,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw Exception(response.data['message'] ?? 'Failed to calculate upgrade price');
    } on DioException catch (e) {
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception(_apiService.getErrorMessage(e));
    }
  }

  /// Create upgrade payment order (or instant free upgrade)
  Future<Map<String, dynamic>> createUpgradeOrder(
    String packageId,
    int targetTierIndex, {
    Map<String, dynamic>? billingAddress,
  }) async {
    try {
      final response = await _apiService.dio.post(
        ApiConstants.activeTierInit,
        data: {
          'package_id': packageId,
          'target_tier_index': targetTierIndex,
          if (billingAddress != null) 'billing_address': billingAddress,
        },
      );

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw Exception(response.data['message'] ?? 'Failed to create upgrade order');
    } on DioException catch (e) {
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception(_apiService.getErrorMessage(e));
    }
  }

  /// Verify upgrade payment
  Future<GatewayVerificationResponse> verifyUpgradePayment({
    required String paymentSessionId,
    required String paymentId,
    String? signature,
  }) async {
    return await _gatewayService.confirmSession(
      endpoint: ApiConstants.activeTierConfirm,
      paymentSessionId: paymentSessionId,
      paymentId: paymentId,
      signature: signature,
    );
  }

  /// Fetch video playback data (HLS URL, metadata) for a given video ID.
  Future<Map<String, dynamic>> getVideoPlaybackData(String videoId) async {
    try {
      debugPrint('DashboardService: fetching playback data for video=$videoId');

      final response = await _apiService.dio.get(
        ApiConstants.videoPlayback(videoId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final videoData = response.data['data']['video'] as Map<String, dynamic>;
        debugPrint('DashboardService: playback data received for video=$videoId');
        return videoData;
      }

      throw Exception('Failed to load video playback data');
    } on DioException catch (e) {
      debugPrint('DashboardService: playback fetch error - ${e.message}');
      if (e.response?.statusCode == 403) {
        throw Exception('You do not have access to this video');
      }
      if (e.response?.statusCode == 404) {
        throw Exception('Video not found');
      }
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('DashboardService: unexpected playback error - $e');
      rethrow;
    }
  }

  /// Clear all caches
  void clearCache() {
    debugPrint('=== DashboardService: Clearing cache ===');
    _cachedFaculty = null;
    _lastFacultyFetch = null;
    _cachedPackages = null;
    _lastPackagesFetch = null;
    _cachedPackagesSubjectId = null;
    _cachedPackagesType = null;
  }
}
