// ----------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------

/**
 * @file
 * coo.cuh
 *
 * @brief Coordinate Format (a.k.a. triplet format) Graph Data Structure
 */


#include <stdio.h>

#include <algorithm>

/**
 * @brief COO sparse format edge. (A COO graph is just a
 * list/array/vector of these.)
 */
template<typename VertexId, typename Value>
struct Coo {
    VertexId row;
    VertexId col;
    Value val;

    Coo(VertexId row, VertexId col, Value val) : row(row), col(col), val(val) {}

    void Val(Value &value) {
        value = val;
    }
};


/*template<typename VertexId>
struct Coo<VertexId, util::NullType> {
    VertexId row;
    VertexId col;

    template <typename Value>
    Coo(VertexId row, VertexId col, Value val) : row(row), col(col) {}

    template <typename Value>
    void Val(Value &value) {}
};*/


/**
 * @brief Comparator for sorting COO sparse format edges first by row
 *
 * @tparam Coo COO Datatype
 * @param[in] elem1 First element to compare
 * @param[in] elem2 Second element to compare
 * @returns true if first element comes before second element in (r,c)
 * order, otherwise false
 *
 * @see ColumnFirstTupleCompare
 */
template<typename Coo>
bool RowFirstTupleCompare (
    Coo elem1,
    Coo elem2) {
    if (elem1.row < elem2.row) {
        // Sort edges by source node
        return true;
    } else if ((elem1.row == elem2.row) && (elem1.col < elem2.col)) {
        // Sort edgelists as well for coherence
        return true;
    }

    return false;
}

/**
 * @brief Comparator for sorting COO sparse format edges first by column
 *
 * @param[in] elem1 First element to compare
 * @param[in] elem2 Second element to compare
 * @returns true if first element comes before second element in (c,r)
 * order, otherwise false
 *
 * @see RowFirstTupleCompare
 */
template<typename Coo>
bool ColumnFirstTupleCompare (
    Coo elem1,
    Coo elem2) {
    if (elem1.col < elem2.col) {
        // Sort edges by source node
        return true;
    } else if ((elem1.col == elem2.col) && (elem1.row < elem2.row)) {
        // Sort edgelists as well for coherence
        return true;
    }

    return false;
}

