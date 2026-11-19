import 'package:flutter/foundation.dart';
import 'package:pgme/core_android/models/book_model.dart';
import 'package:pgme/core_android/models/book_request_model.dart';
import 'package:pgme/core_android/models/gateway_models.dart';
import 'package:pgme/core_android/services/book_service.dart';
import 'package:pgme/core_android/services/book_request_service.dart';

class BookProvider extends ChangeNotifier {
  final BookService _bookService = BookService();
  final BookRequestService _bookRequestService = BookRequestService();

  // Books state
  List<BookModel> _books = [];
  bool _isLoadingBooks = false;
  String? _booksError;
  PaginationInfo? _pagination;
  String? _currentCategory;
  String? _currentSubjectId;
  String? _searchQuery;

  // Cart state
  final Map<String, CartItem> _cart = {};

  // Orders state
  List<BookRequestModel> _orders = [];
  bool _isLoadingOrders = false;
  String? _ordersError;

  // Shipping cost state
  int _shippingCostValue = 0; // Default fallback value (matches backend DEFAULT_SHIPPING_COST)
  String? _shippingCostError;

  // Getters
  List<BookModel> get books => _books;
  bool get isLoadingBooks => _isLoadingBooks;
  String? get booksError => _booksError;
  PaginationInfo? get pagination => _pagination;
  String? get currentCategory => _currentCategory;
  String? get currentSubjectId => _currentSubjectId;
  String? get searchQuery => _searchQuery;

  Map<String, CartItem> get cart => _cart;
  List<CartItem> get cartItems => _cart.values.toList();
  int get cartItemCount => _cart.values.fold(0, (sum, item) => sum + item.quantity);
  bool get isCartEmpty => _cart.isEmpty;

  List<BookRequestModel> get orders => _orders;
  bool get isLoadingOrders => _isLoadingOrders;
  String? get ordersError => _ordersError;
  String? get shippingCostError => _shippingCostError;

  /// Calculate cart subtotal
  num get cartSubtotal {
    return _cart.values.fold<num>(0, (sum, item) => sum + item.totalPrice);
  }

  /// Calculate shipping cost (uses value from backend)
  int get shippingCost => _cart.isNotEmpty ? _shippingCostValue : 0;

  /// Calculate cart total
  num get cartTotal => cartSubtotal + shippingCost;

  /// Load books from API
  Future<void> loadBooks({
    String? category,
    String? subjectId,
    String? search,
    int page = 1,
    bool refresh = false,
  }) async {
    if (_isLoadingBooks && !refresh) return;

    _isLoadingBooks = true;
    _booksError = null;
    if (refresh || page == 1) {
      _books = [];
    }
    notifyListeners();

    try {
      _currentCategory = category;
      _currentSubjectId = subjectId;
      _searchQuery = search;

      final response = await _bookService.getBooks(
        category: category,
        subjectId: subjectId,
        search: search,
        page: page,
      );

      if (page == 1 || refresh) {
        _books = response.books;
      } else {
        _books.addAll(response.books);
      }
      _pagination = response.pagination;
    } catch (e) {
      _booksError = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoadingBooks = false;
      notifyListeners();
    }
  }

  /// Load more books (pagination)
  Future<void> loadMoreBooks() async {
    if (_pagination == null || !_pagination!.hasNext || _isLoadingBooks) return;

    await loadBooks(
      category: _currentCategory,
      subjectId: _currentSubjectId,
      search: _searchQuery,
      page: _pagination!.currentPage + 1,
    );
  }

  /// Search books
  Future<void> searchBooks(String query) async {
    if (query.trim().isEmpty) {
      await loadBooks(refresh: true);
      return;
    }
    await loadBooks(search: query, refresh: true);
  }

  /// Filter by category
  Future<void> filterByCategory(String? category) async {
    await loadBooks(category: category, refresh: true);
  }

  /// Add item to cart
  void addToCart(BookModel book, {int quantity = 1}) {
    final wasEmpty = _cart.isEmpty;

    if (_cart.containsKey(book.bookId)) {
      _cart[book.bookId]!.quantity += quantity;
    } else {
      _cart[book.bookId] = CartItem(
        bookId: book.bookId,
        title: book.title,
        author: book.author,
        thumbnailUrl: book.thumbnailUrl,
        price: book.actualPrice,
        quantity: quantity,
      );
    }
    notifyListeners();

    // Fetch shipping cost from backend when first item is added
    if (wasEmpty) {
      _shippingCostError = null; // Clear any previous errors
      fetchShippingCost().catchError((error) {
        debugPrint('Error fetching shipping cost: $error');
        // Set error state - UI should display this to the user
        _shippingCostError = error.toString().replaceAll('Exception: ', '');
        notifyListeners();
      });
    }
  }

  /// Remove item from cart
  void removeFromCart(String bookId) {
    _cart.remove(bookId);
    notifyListeners();
  }

  /// Update cart item quantity
  void updateCartQuantity(String bookId, int quantity) {
    if (!_cart.containsKey(bookId)) return;

    if (quantity <= 0) {
      _cart.remove(bookId);
    } else {
      _cart[bookId]!.quantity = quantity;
    }
    notifyListeners();
  }

  /// Increment cart item quantity
  void incrementQuantity(String bookId) {
    if (_cart.containsKey(bookId)) {
      _cart[bookId]!.quantity++;
      notifyListeners();
    }
  }

  /// Decrement cart item quantity
  void decrementQuantity(String bookId) {
    if (_cart.containsKey(bookId)) {
      if (_cart[bookId]!.quantity > 1) {
        _cart[bookId]!.quantity--;
      } else {
        _cart.remove(bookId);
      }
      notifyListeners();
    }
  }

  /// Clear cart
  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  /// Check if book is in cart
  bool isInCart(String bookId) {
    return _cart.containsKey(bookId);
  }

  /// Get cart item quantity for a book
  int getCartQuantity(String bookId) {
    return _cart[bookId]?.quantity ?? 0;
  }

  /// Get cart items as order items format
  List<Map<String, dynamic>> getCartAsOrderItems() {
    return _cart.values.map((item) => item.toOrderItem()).toList();
  }

  /// Create order (with Razorpay)
  Future<BookRequestResponse> createOrder({
    required String recipientName,
    required String shippingPhone,
    required String shippingAddress,
  }) async {
    final items = getCartAsOrderItems();
    return await _bookRequestService.createOrder(
      items: items,
      recipientName: recipientName,
      shippingPhone: shippingPhone,
      shippingAddress: shippingAddress,
    );
  }

  /// Verify payment
  Future<RequestVerifyResponse> verifyPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final response = await _bookRequestService.verifyAccess(
      razorpayOrderId: razorpayOrderId,
      razorpayPaymentId: razorpayPaymentId,
      razorpaySignature: razorpaySignature,
    );

    // Clear cart on successful payment
    if (response.success) {
      clearCart();
    }

    return response;
  }

  /// Create test order (bypasses Razorpay)
  Future<Map<String, dynamic>> createTestOrder({
    required String recipientName,
    required String shippingPhone,
    required String shippingAddress,
  }) async {
    final items = getCartAsOrderItems();
    final response = await _bookRequestService.createTestRequest(
      items: items,
      recipientName: recipientName,
      shippingPhone: shippingPhone,
      shippingAddress: shippingAddress,
    );

    // Clear cart on successful order
    if (response['success'] == true) {
      clearCart();
    }

    return response;
  }

  // ============================================================================
  // GATEWAY METHODS
  // ============================================================================

  /// Create gateway session for book order
  Future<GatewaySession> initSession({
    required String recipientName,
    required String shippingPhone,
    required String shippingAddress,
    Map<String, dynamic>? billingAddress,
    Map<String, dynamic>? shippingAddressStructured,
  }) async {
    final items = getCartAsOrderItems();
    return await _bookRequestService.initSession(
      items: items,
      recipientName: recipientName,
      shippingPhone: shippingPhone,
      shippingAddress: shippingAddress,
      billingAddress: billingAddress,
      shippingAddressStructured: shippingAddressStructured,
    );
  }

  /// Verify gateway payment for book request
  Future<GatewayVerificationResponse> confirmSession({
    required String paymentSessionId,
    required String paymentId,
    String? signature,
  }) async {
    final result = await _bookRequestService.confirmSession(
      paymentSessionId: paymentSessionId,
      paymentId: paymentId,
      signature: signature,
    );

    // Clear cart on successful payment
    if (result.success) {
      clearCart();
    }

    return result;
  }

  /// Load user's orders
  Future<void> loadOrders({bool refresh = false}) async {
    if (_isLoadingOrders && !refresh) return;

    _isLoadingOrders = true;
    _ordersError = null;
    if (refresh) {
      _orders = [];
    }
    notifyListeners();

    try {
      _orders = await _bookRequestService.getUserRequests();
    } catch (e) {
      _ordersError = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoadingOrders = false;
      notifyListeners();
    }
  }

  /// Get order by ID
  Future<BookRequestModel> getOrderById(String orderId) async {
    return await _bookRequestService.getRequestById(orderId);
  }

  /// Cancel order
  Future<void> cancelOrder(String orderId) async {
    await _bookRequestService.cancelRequest(orderId);
    // Refresh orders list
    await loadOrders(refresh: true);
  }

  /// Fetch shipping cost from backend
  /// Throws exception if fetch fails - caller should handle errors
  Future<void> fetchShippingCost() async {
    final cost = await _bookService.getShippingCost();
    _shippingCostValue = cost;
    notifyListeners();
  }

  /// Clear all state
  void clearAll() {
    _books = [];
    _booksError = null;
    _pagination = null;
    _currentCategory = null;
    _searchQuery = null;
    _cart.clear();
    _orders = [];
    _ordersError = null;
    notifyListeners();
  }
}
