//
//  CoreDataManager.swift
//  TakeEatEasy
//
//  Created by Nadezhda Zenkova on 10.11.2021.
//

import UIKit
import CoreData

protocol CoreDataServiceProtocol {
    
    func saveContext()
    func fetchRecentMeal() -> [MealModel]?
    func fetchAllMeals() -> [MealModel]?
    func meal(with id: NSManagedObjectID) -> MealModel?
    func addNewMeal(mealModel: MealModel)
    func changeMeal(mealModel: MealModel)
    func removeMeal(_ mealModel: MealModel)
    func fetchMealStatistics() -> [MealModel]?
    func fetchTags(meal: MealModel) -> [TagModel]
    func fetchPopularTags(amount: Int) -> [TagModel]?
    func addTag(tagModel: TagModel, in mealModel: MealModel)
    func removeTag(tagModel: TagModel, in mealModel: MealModel)
}


class CoreDataService: NSObject, CoreDataServiceProtocol {
    let persistentContainer: NSPersistentContainer
    
    lazy var managedObjectContext: NSManagedObjectContext = {
        persistentContainer.newBackgroundContext()
    }()
    
    init(container: String) {
        persistentContainer = NSPersistentContainer(name: container)
        persistentContainer.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
    }
    
    func saveContext() {
        guard managedObjectContext.hasChanges else { return }
        try? managedObjectContext.save()
    }
    
    //
    // MARK: - Meals
    //
    
    func fetchRecentMeal() -> [MealModel]? {
        return fetchMeals(limit: 1)
    }
    
    func fetchAllMeals() -> [MealModel]? {
        return fetchMeals()
    }
    
    func meal(with id: NSManagedObjectID) -> MealModel? {
        guard let meal = getMeal(by: id) else { return nil }
        return meal.mealModel
    }
    
    func addNewMeal(mealModel: MealModel) {
        let meal = Meal(context: managedObjectContext)
        meal.name = mealModel.name
        meal.date = mealModel.date
        meal.picture = mealModel.picture.toData
        meal.mood = mealModel.mood?.rawValue ?? 0
        meal.moodAfter = mealModel.moodAfter?.rawValue ?? 0
        meal.tags = NSSet(array: [])
        meal.tagsStrings = mealModel.tagStrings ?? []
        
        for tag in mealModel.tagStrings ?? [] {
            let newTag = Tag(context: managedObjectContext)
            newTag.tag = tag
            newTag.meal = meal
        }
        
        
        saveContext()
    }
    
    func changeMeal(mealModel: MealModel) {
        guard let id = mealModel.id else { return }
        
        managedObjectContext.perform { [weak self] in
            if let meal = try? self?.managedObjectContext.existingObject(with: id) as? Meal {
                meal.update(with: mealModel)
                self?.saveContext()
            }
        }
    }
    
    func removeMeal(_ mealModel: MealModel) {
        guard let id = mealModel.id else { return }
        let meal = managedObjectContext.object(with: id)
        managedObjectContext.delete(meal)
        saveContext()
    }
    
    func fetchMealStatistics() -> [MealModel]? {
        let request: NSFetchRequest<Meal> = Meal.fetchRequest()
        request.predicate = NSPredicate(format: "mood.rawValue != nil && moodAfter.rawValue != nil")
        request.sortDescriptors = [mealStatisticsSortDescriptor]
        let meals: [Meal]? = try? managedObjectContext.fetch(request)
        return meals?.map{$0.mealModel}
    }
    
    //
    // MARK: - Tags
    //
    
    func fetchTags(meal: MealModel) -> [TagModel] {
        let sortDescriptor = NSSortDescriptor(key: "tag", ascending: true)
        guard let id = meal.id,
              let meal = getMeal(by: id),
              let tags = meal.tags?.sortedArray(using: [sortDescriptor]) as? [Tag]
        else {
            return []
        }
        return tags.map { $0.tagModel }
    }
    
    func fetchPopularTags(amount: Int) -> [TagModel]? {
        let tags: [Tag]? = try? managedObjectContext.fetch(Tag.fetchRequest())
        let sortedTags = tags?.map{$0.tagModel}.sorted(by: {$0.tag.count > $1.tag.count })
        let firstTags = sortedTags?.limit(amount)
        
        return firstTags
    }
    
    func addTag(tagModel: TagModel, in meal: MealModel) {
        guard let mealID = meal.id, let meal = getMeal(by: mealID) else { return }
        
        let tag = Tag(context: managedObjectContext)
        tag.tag = tagModel.tag
        meal.addToTags(tag)
        
        saveContext()
    }
    
    func removeTag(tagModel: TagModel, in mealModel: MealModel) {
        guard let tagID = tagModel.id,
              let mealID = mealModel.id,
              let tag = getTag(by: tagID),
              let meal = getMeal(by: mealID) else { return }
        
        meal.removeFromTags(tag)
        
        saveContext()
    }
    
    //
    // MARK: - Private Methods
    //
    
    private func getMeal(by id: NSManagedObjectID) -> Meal? {
        return managedObjectContext.object(with: id) as? Meal
    }
    
    private func getTag(by id: NSManagedObjectID) -> Tag? {
        return managedObjectContext.object(with: id) as? Tag
    }
    
    private func fetchMeals(limit: Int? = nil) -> [MealModel]? {
        let request: NSFetchRequest<Meal> = Meal.fetchRequest()
        request.sortDescriptors = [recentMealSortDescriptor]
        request.fetchLimit = limit ?? 0
        guard let meals = try? managedObjectContext.fetch(request) else {
            return nil
        }
        return meals.compactMap { $0.mealModel }
    }
    
    private var recentMealSortDescriptor: NSSortDescriptor {
        return NSSortDescriptor(key: "date", ascending: false)
    }
    
    private var mealStatisticsSortDescriptor: NSSortDescriptor {
        return NSSortDescriptor(key: "date", ascending: true)
    }
}


extension Meal {
    func update(with mealModel: MealModel) {
        name = mealModel.name
        date = mealModel.date
        picture = mealModel.picture.toData
        mood = mealModel.mood?.rawValue ?? 3
        moodAfter = mealModel.moodAfter?.rawValue ?? 3
        tags = NSSet(array: mealModel.tags ?? [])
    }
}
