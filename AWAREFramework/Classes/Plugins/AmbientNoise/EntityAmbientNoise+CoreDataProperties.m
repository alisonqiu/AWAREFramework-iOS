//
//  EntityAmbientNoise+CoreDataProperties.m
//  
//
//  Created by Yuuki Nishiyama on 2018/03/12.
//
//

#import "EntityAmbientNoise+CoreDataProperties.h"

@implementation EntityAmbientNoise (CoreDataProperties)

+ (NSFetchRequest<EntityAmbientNoise *> *)fetchRequest {
    NSLog(@"(NSFetchRequest<EntityAmbientNoise *> *)fetchRequest");
	return [[NSFetchRequest alloc] initWithEntityName:@"EntityAmbientNoise"];
}

@dynamic device_id;
@dynamic double_decibels;
@dynamic double_frequency;
@dynamic double_prob;
@dynamic double_silent_threshold;
@dynamic is_silent;
@dynamic raw;
@dynamic timestamp;
@dynamic dnn_res;

@end
