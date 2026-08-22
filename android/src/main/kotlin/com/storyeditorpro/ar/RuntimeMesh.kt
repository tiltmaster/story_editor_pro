package com.storyeditorpro.ar

import android.content.Context
import android.graphics.Color
import org.json.JSONObject

internal data class MeshVertex(val x: Float, val y: Float, val z: Float)
internal data class MeshTriangle(val a: Int, val b: Int, val c: Int, val materialId: Int)

internal data class RuntimeMesh(
    val vertices: List<MeshVertex>,
    val triangles: List<MeshTriangle>,
    val materialColors: Map<Int, Int>,
) {
    companion object {
        fun load(context: Context, assetPath: String): RuntimeMesh {
            val text = context.assets.open(assetPath).bufferedReader().use { it.readText() }
            val root = JSONObject(text)
            require(root.getInt("schema_version") == 1) { "Unsupported runtime mesh schema" }

            val verticesJson = root.getJSONArray("vertices")
            val vertices = ArrayList<MeshVertex>(verticesJson.length())
            for (index in 0 until verticesJson.length()) {
                val value = verticesJson.getJSONArray(index)
                vertices += MeshVertex(
                    value.getDouble(0).toFloat(),
                    value.getDouble(1).toFloat(),
                    value.getDouble(2).toFloat(),
                )
            }

            val triangleJson = root.getJSONArray("triangles")
            val materialIds = root.getJSONArray("triangle_material_ids")
            require(triangleJson.length() == materialIds.length()) { "Invalid material table" }
            val triangles = ArrayList<MeshTriangle>(triangleJson.length())
            for (index in 0 until triangleJson.length()) {
                val value = triangleJson.getJSONArray(index)
                val a = value.getInt(0)
                val b = value.getInt(1)
                val c = value.getInt(2)
                require(a in vertices.indices && b in vertices.indices && c in vertices.indices) {
                    "Invalid mesh index"
                }
                triangles += MeshTriangle(a, b, c, materialIds.getInt(index))
            }

            val colors = mutableMapOf<Int, Int>()
            val groups = root.getJSONArray("material_groups")
            for (index in 0 until groups.length()) {
                val group = groups.getJSONObject(index)
                val rgba = group.getJSONArray("base_color_rgba")
                fun channel(position: Int) =
                    (rgba.getDouble(position).coerceIn(0.0, 1.0) * 255.0).toInt()
                colors[group.getInt("material_id")] = Color.argb(
                    channel(3),
                    channel(0),
                    channel(1),
                    channel(2),
                )
            }
            return RuntimeMesh(vertices, triangles, colors)
        }
    }
}
