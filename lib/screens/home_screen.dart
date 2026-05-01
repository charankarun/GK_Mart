import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'cart_screen.dart';
import 'product_detail_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FocusNode searchFocusNode = FocusNode();
  final TextEditingController searchController = TextEditingController();
  String searchQuery = "";

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _readString(Map<String, dynamic> data, String key,
      {String fallback = ''}) {
    final value = data[key]?.toString().trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  @override
  void dispose() {
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Hello",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('carts')
                      .doc(user.uid)
                      .collection('items')
                      .snapshots(),
                  builder: (context, snapshot) {
                    int count = 0;

                    if (snapshot.hasData) {
                      for (final doc in snapshot.data!.docs) {
                        count += _readInt(doc.data()['quantity']);
                      }
                    }

                    return Stack(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.shopping_cart),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const CartScreen()),
                            );
                          },
                        ),
                        if (count > 0)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                "$count",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.grey.shade200, blurRadius: 5),
              ],
            ),
            child: TextField(
              controller: searchController,
              focusNode: searchFocusNode,
              decoration: InputDecoration(
                icon: const Icon(Icons.search),
                hintText: "Search products or categories...",
                border: InputBorder.none,
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            searchController.clear();
                            searchQuery = "";
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Colors.deepPurpleAccent],
              ),
            ),
            child: const Center(
              child: Text(
                "50% OFF on Groceries",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              "Categories",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  FirebaseFirestore.instance.collection('categories').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text("Unable to load categories"));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final categories = snapshot.data!.docs;

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final data = categories[index].data();
                    final name = _readString(data, 'name', fallback: 'Category');
                    final imageUrl = _readString(data, 'image');

                    return Container(
                      width: 80,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.shade200,
                            blurRadius: 5,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundImage: imageUrl.isNotEmpty
                                ? NetworkImage(imageUrl)
                                : null,
                            child: imageUrl.isEmpty
                                ? const Icon(Icons.image)
                                : null,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            name,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              "Trending Products",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  FirebaseFirestore.instance.collection('products').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text("Unable to load products"));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allProducts = snapshot.data!.docs;
                final filteredProducts = allProducts.where((product) {
                  final data = product.data();
                  final name = _readString(data, 'name').toLowerCase();
                  final category = _readString(data, 'category').toLowerCase();

                  return name.contains(searchQuery) ||
                      category.contains(searchQuery);
                }).toList();

                if (filteredProducts.isEmpty) {
                  return const Center(child: Text("No products found"));
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('carts')
                      .doc(user.uid)
                      .collection('items')
                      .snapshots(),
                  builder: (context, cartSnapshot) {
                    final cartQtyById = <String, int>{};

                    if (cartSnapshot.hasData) {
                      for (final doc in cartSnapshot.data!.docs) {
                        cartQtyById[doc.id] = _readInt(doc.data()['quantity']);
                      }
                    }

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('wishlist')
                          .doc(user.uid)
                          .collection('items')
                          .snapshots(),
                      builder: (context, wishlistSnapshot) {
                        final wishlistIds = <String>{};

                        if (wishlistSnapshot.hasData) {
                          for (final doc in wishlistSnapshot.data!.docs) {
                            wishlistIds.add(doc.id);
                          }
                        }

                        return GridView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredProducts.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.85,
                          ),
                          itemBuilder: (context, index) {
                            final product = filteredProducts[index];
                            final productData = product.data();
                            final name = _readString(
                              productData,
                              'name',
                              fallback: 'Product',
                            );
                            final unit = _readString(productData, 'unit');
                            final imageUrl = _readString(productData, 'image');
                            final price = productData['price'] ?? 0;
                            final outOfStock =
                                productData['outOfStock'] == true;
                            final isWishlisted =
                                wishlistIds.contains(product.id);
                            final qty = cartQtyById[product.id] ?? 0;

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProductDetailScreen(
                                      product: {
                                        ...productData,
                                        'name': name,
                                        'price': price,
                                        'unit': unit,
                                        'image': imageUrl,
                                      },
                                      productId: product.id,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                            top: Radius.circular(16),
                                          ),
                                          child: imageUrl.isNotEmpty
                                              ? Image.network(
                                                  imageUrl,
                                                  height: 80,
                                                  width: double.infinity,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) {
                                                    return _imagePlaceholder();
                                                  },
                                                )
                                              : _imagePlaceholder(),
                                        ),
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: GestureDetector(
                                            onTap: () async {
                                              final wishRef =
                                                  FirebaseFirestore.instance
                                                      .collection('wishlist')
                                                      .doc(user.uid)
                                                      .collection('items');

                                              if (isWishlisted) {
                                                await wishRef
                                                    .doc(product.id)
                                                    .delete();
                                              } else {
                                                await wishRef
                                                    .doc(product.id)
                                                    .set({
                                                  'name': name,
                                                  'price': price,
                                                  'image': imageUrl,
                                                  'unit': unit,
                                                });
                                              }
                                            },
                                            child: AnimatedScale(
                                              duration: const Duration(
                                                milliseconds: 200,
                                              ),
                                              scale:
                                                  isWishlisted ? 1.2 : 1.0,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(4),
                                                decoration:
                                                    const BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  isWishlisted
                                                      ? Icons.favorite
                                                      : Icons.favorite_border,
                                                  color: Colors.red,
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (outOfStock)
                                          Positioned(
                                            left: 6,
                                            top: 6,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.black87,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                "Out of stock",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            unit,
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  "\u20B9$price",
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFF15803D),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                              if (outOfStock)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        Colors.grey.shade400,
                                                    borderRadius:
                                                        BorderRadius.circular(6),
                                                  ),
                                                  child: const Text(
                                                    "NA",
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                )
                                              else if (qty == 0)
                                                GestureDetector(
                                                  onTap: () async {
                                                    final cartRef =
                                                        FirebaseFirestore
                                                            .instance
                                                            .collection('carts')
                                                            .doc(user.uid)
                                                            .collection('items');

                                                    await cartRef
                                                        .doc(product.id)
                                                        .set({
                                                      'name': name,
                                                      'price': price,
                                                      'unit': unit,
                                                      'quantity': 1,
                                                      'image': imageUrl,
                                                    });
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 10,
                                                      vertical: 5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          const Color(0xFF16A34A),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        6,
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      "ADD",
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              else
                                                Container(
                                                  decoration: BoxDecoration(
                                                    border: Border.all(
                                                      color: Colors.green,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(6),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      InkWell(
                                                        onTap: () async {
                                                          final itemRef =
                                                              FirebaseFirestore
                                                                  .instance
                                                                  .collection(
                                                                      'carts')
                                                                  .doc(user.uid)
                                                                  .collection(
                                                                      'items')
                                                                  .doc(
                                                                    product.id,
                                                                  );

                                                          if (qty <= 1) {
                                                            await itemRef
                                                                .delete();
                                                          } else {
                                                            await itemRef
                                                                .update({
                                                              'quantity':
                                                                  FieldValue
                                                                      .increment(
                                                                -1,
                                                              ),
                                                            });
                                                          }
                                                        },
                                                        child: const Padding(
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                            horizontal: 6,
                                                          ),
                                                          child: Icon(
                                                            Icons.remove,
                                                            size: 16,
                                                          ),
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 6,
                                                        ),
                                                        child: Text("$qty"),
                                                      ),
                                                      InkWell(
                                                        onTap: () async {
                                                          await FirebaseFirestore
                                                              .instance
                                                              .collection(
                                                                  'carts')
                                                              .doc(user.uid)
                                                              .collection(
                                                                  'items')
                                                              .doc(product.id)
                                                              .set({
                                                            'quantity':
                                                                FieldValue
                                                                    .increment(
                                                              1,
                                                            ),
                                                          }, SetOptions(merge: true));
                                                        },
                                                        child: const Padding(
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                            horizontal: 6,
                                                          ),
                                                          child: Icon(
                                                            Icons.add,
                                                            size: 16,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 80,
      width: double.infinity,
      color: Colors.grey.shade100,
      child: const Center(child: Icon(Icons.image)),
    );
  }
}
