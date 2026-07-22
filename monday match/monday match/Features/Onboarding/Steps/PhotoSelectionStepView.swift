import SwiftUI
import PhotosUI

struct PhotoSelectionStepView: View {
    let photos: [ProfilePhoto]
    let maximumPhotos: Int
    let errorMessage: String?
    let onAddPhotoData: ([Data]) -> Void
    let onRemovePhoto: (UUID) -> Void
    let onMovePhoto: (IndexSet, Int) -> Void

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoadingSelection = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                header

                if photos.isEmpty {
                    emptyState
                } else {
                    photoList
                }

                pickerButton

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppTypography.caption)
                        .foregroundStyle(.red)
                }

                AppCard {
                    HStack(alignment: .top, spacing: AppSpacing.medium) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(AppColors.accent)

                        Text(
                            "Photos are compressed locally before upload. Metadata is not intentionally preserved in the processed JPEG."
                        )
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryForeground)
                    }
                }
            }
            .padding(AppSpacing.large)
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            loadSelectedItems(newItems)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Add your best photos")
                .font(AppTypography.title)

            Text(
                "Add at least one and up to \(maximumPhotos) photos. The first photo becomes your main profile photo."
            )
            .font(AppTypography.body)
            .foregroundStyle(AppColors.secondaryForeground)
            .lineSpacing(4)
        }
    }

    private var emptyState: some View {
        AppCard {
            VStack(spacing: AppSpacing.medium) {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(AppColors.accent)

                Text("No photos added yet")
                    .font(AppTypography.headline)

                Text(
                    "Choose a clear, recent photo where your face is easy to recognize."
                )
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryForeground)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var photoList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Your photos")
                .font(AppTypography.headline)

            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                ProfilePhotoRow(
                    photo: photo,
                    position: index,
                    isMainPhoto: index == 0,
                    canMoveUp: index > 0,
                    canMoveDown: index < photos.count - 1,
                    onRemove: {
                        onRemovePhoto(photo.id)
                    },
                    onMoveUp: {
                        onMovePhoto(
                            IndexSet(integer: index),
                            index - 1
                        )
                    },
                    onMoveDown: {
                        onMovePhoto(
                            IndexSet(integer: index),
                            index + 2
                        )
                    }
                )
            }
        }
    }

    private var pickerButton: some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: max(0, maximumPhotos - photos.count),
            matching: .images
        ) {
            HStack(spacing: AppSpacing.small) {
                if isLoadingSelection {
                    ProgressView()
                } else {
                    Image(systemName: "photo.badge.plus")
                }

                Text(
                    photos.count >= maximumPhotos
                        ? "Maximum reached"
                        : "Choose photos"
                )
            }
            .font(AppTypography.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.medium)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .disabled(isLoadingSelection || photos.count >= maximumPhotos)
    }

    private func loadSelectedItems(_ items: [PhotosPickerItem]) {
        isLoadingSelection = true

        Task {
            var loadedData: [Data] = []

            for item in items {
                if let data = try? await item.loadTransferable(
                    type: Data.self
                ) {
                    loadedData.append(data)
                }
            }

            await MainActor.run {
                onAddPhotoData(loadedData)
                selectedItems = []
                isLoadingSelection = false
            }
        }
    }
}

private struct ProfilePhotoRow: View {
    let photo: ProfilePhoto
    let position: Int
    let isMainPhoto: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onRemove: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Group {
                if let uiImage = UIImage(data: photo.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .padding(AppSpacing.large)
                        .foregroundStyle(AppColors.secondaryForeground)
                }
            }
            .frame(width: 92, height: 112)
            .background(AppColors.secondaryBackground)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .clipped()

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(
                    isMainPhoto
                        ? "Main photo"
                        : "Photo \(position + 1)"
                )
                .font(AppTypography.headline)

                if isMainPhoto {
                    Text("Shown first on your profile")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryForeground)
                }

                HStack(spacing: AppSpacing.small) {
                    Button(action: onMoveUp) {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(!canMoveUp)

                    Button(action: onMoveDown) {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(!canMoveDown)

                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }

            Spacer()
        }
        .padding(AppSpacing.medium)
        .background(AppColors.secondaryBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
    }
}

#Preview {
    PhotoSelectionStepView(
        photos: [],
        maximumPhotos: 3,
        errorMessage: nil,
        onAddPhotoData: { _ in },
        onRemovePhoto: { _ in },
        onMovePhoto: { _, _ in }
    )
}
